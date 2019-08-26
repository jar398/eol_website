# export SERVER="http://127.0.0.1:3000/"
# export TOKEN=`cat ~/Sync/eol/admin.token`
# COMMAND=flush ruby -r ./lib/painter.rb -e Painter.main

# You might want to put 'config.log_level = :warn'
# in config/environments/development.rb
# to reduce noise emitted to console.

require 'csv'

# These are required if we want to be an HTTP client:
require 'net/http'
require 'json'
require 'cgi'

class Painter

  @silly_resource = 99999
  @silly_file = "directives.tsv"
  @page_origin = 500000000

  START_TERM = "https://eol.org/schema/terms/starts_at"
  STOP_TERM  = "https://eol.org/schema/terms/stops_at"
  SILLY_TERM = "http://example.org/numlegs"
  LIMIT = 1000000

  def self.main
    server = ENV['SERVER'] || "https://eol.org/"
    token = ENV['TOKEN'] || STDERR.puts("** No TOKEN provided")
    query_fn = Proc.new {|cql| query_via_http(server, token, cql)}
    painter = new(query_fn)

    command = ENV["COMMAND"]
    if ENV.key?("RESOURCE")
      resource = Integer(ENV["RESOURCE"])
    else
      resource = @silly_resource
    end

    case command
    when "infer" then    # list the inferences
      painter.infer(resource)
    when "paint" then    # assert the inferences
      painter.paint(resource)
    else
      painter.debug(command, resource)
    end
  end

  def initialize(query_fn)
    @query_fn = query_fn
    @paginator = Paginator(query_fn)
    @pagesize = 10000
  end

  # Do branch painting based on directives that are already in the graphdb.

  def infer(resource)
    paint_or_infer(resource, "", "")
  end

  def paint(resource)
    paint_or_infer(resource,
                   "MERGE (q)-[:inferred_trait]->(t)",
                   ", (q)-[i:inferred_trait]->(t) DELETE i")
  end

  def paint_or_infer(resource, merge, delete)
    show_directives(resource)

    # Propagate traits from start point to descendants.  Filter by resource.
    # Currently assumes the painted trait has an object_term, but this
    # should be generalized to allow measurement as well
    query = 
         "MATCH (r:Resource {resource_id: #{resource}})<-[:supplier]-
                (t:Trait)-[:metadata]->
                (m:MetaData)-[:predicate]->
                (:Term {uri: '#{START_TERM}'}),
                (t)-[:object_term]->(o:Term)
          WITH t, o, toInteger(m.measurement) as ancestor
          MATCH (a:Page {page_id: ancestor})<-[:parent*1..]-(d:Page)
          #{merge}
          RETURN d.page_id, t.eol_pk, t.measurement, o.name, d.canonical
          LIMIT #{LIMIT}"
    STDERR.puts(query)
    assert_path = "assert.csv"
    r = run_paged_query(query, @pagesize, assert_path)
    return unless r
    #STDERR.puts("Starts query: #{r["data"].size} rows")

    # Index inferences to prepare for deletion
    inferences = {}

    # OOPS. NEED TO READ THE BIG CSV FILE...

    r["data"].each do |page, trait, value, ovalue, name|
      inferences[[page, trait]] = [name, value, ovalue]
    end
    STDERR.puts("Found #{inferences.size} potential inferences")

    # Erase inferred traits from stop point to descendants.
    query = 
         "MATCH (r:Resource {resource_id: #{resource}})<-[:supplier]-
                (t:Trait)-[:metadata]->
                (m:MetaData)-[:predicate]->
                (:Term {uri: '#{STOP_TERM}'}),
                (p:Page)-[:trait]->(t)
          WITH p, t, toInteger(m.measurement) as ancestor
          MATCH (a:Page {page_id: ancestor})<-[:parent*1..]-(d:Page)
          #{delete}
          RETURN d.page_id, t.eol_pk, ancestor, a.canonical, p.page_id, p.canonical
          LIMIT #{LIMIT}"
    retract_path = "retract.csv"
    r = run_paged_query(query, @pagesize, retract_path)
    if r
      winners = 0
      losers = 0
      orphans = {}
      #STDERR.puts("Stops query: #{r["data"].size} rows")
      # Delete stopped inferences
      r["data"].each do |page, trait, stop_point, stop_name, org_id, org_name|
        if inferences.include?([page, trait])
          winners += 1
        else
          losers += 1
          orphans[stop_point] = [stop_name, org_id, org_name]
        end
      end
      # Show the orphans
      if orphans.size > 0
        STDERR.puts("#{orphans.size} painted pages under stop points are not under start points:")
        orphans.each do |stop_point, info|
          (stop_name, org_id, org_name) = info
          STDERR.puts("#{stop_point},#{stop_name},#{org_id},#{org_name}")
        end
      end
      STDERR.puts("Deleting #{winners} inferences, failing to delete #{losers} inferences")

      # Now actually delete them
      r["data"].each do |page, trait, stop_point, stop_name, org_id, org_name|
        inferences.delete([page, trait])
      end
    end

    # Write remaining inferences to stdout as CSV
    CSV($stdout.dup) do |csv|
      csv << ["page", "name", "trait", "value"]
      inferences.each do |key, info|
        (page, trait) = key
        (name, value, ovalue) = info
        csv << [page, name, trait, value, ovalue]
      end
    end

    # show(resource)
  end

  # For long-running queries (writes to

  def run_paged_query(cql, pagesize, path)
    Paginator(@query_fn).supervise_query(cql, nil, pagesize, path)
  end

  # For small / debugging queries

  def run_query(cql)
    # TraitBank::query(cql)
    json = @query_fn.call(cql)
    if json && json["data"].length > 100
      # Throttle load on server
      sleep(1)
    end
    json
  end

  # A particular query method for doing queries using the EOL v3 API over HTTP
  # CODE COPIED FROM traits_dumper.rb - we might want to facto this out...

  def self.query_via_http(server, token, cql)
    # Need to be a web client.
    # "The Ruby Toolbox lists no less than 25 HTTP clients."
    escaped = CGI::escape(cql)
    uri = URI("#{server}service/cypher?query=#{escaped}")
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "JWT #{token}"
    use_ssl = uri.scheme.start_with?("https")
    response = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => use_ssl) {|http|
      http.request(request)
    }
    if response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)    # can return nil
    else
      STDERR.puts(response.body)
      nil
    end
  end

  # ------------------------------------------------------------------
  # Everything from here down is for debugging.

  def debug(command, resource)
    case command
    when "init" then
      populate(resource, @page_origin)
    when "test" then            # Add some directives
      test(resource, @page_origin)
    when "load" then
      filename = get_directives_filename
      load_directives(filename, resource)
    when "show" then
      show(resource)
    when "directives" then
      show_directives(resource)
    when "flush" then
      flush(resource)
    else
      STDERR.puts("Unrecognized command: #{command}")
    end
  end

  def get_directives_filename
    if ENV.key?("DIRECTIVES")
      ENV["DIRECTIVES"]
    else
      @silly_file
    end
  end

  def show_directives(resource)
    show_stxx_directives(resource, START_TERM, "Start")
    show_stxx_directives(resource, STOP_TERM, "Stop")
  end

  def show_stxx_directives(resource, uri, tag)
    r = run_query(
        "MATCH (r:Resource {resource_id: #{resource}})<-[:supplier]-
               (t:Trait)-[:metadata]->
               (m:MetaData)-[:predicate]->
               (:Term {uri: '#{uri}'}),
               (p:Page)-[:trait]->(t)
         WITH p, t, toInteger(m.measurement) as point_id
         MATCH (point:Page {page_id: point_id})
         RETURN point.page_id, point.canonical, t.eol_pk, p.page_id, p.canonical
         LIMIT 10000")
    if r
      STDERR.puts("#{r["data"].size} stop directives")
      r["data"][0..10].map{|row| STDERR.puts("#{tag} directive: #{row}")} if r
    end
  end

  # Load directives from TSV file... this was just for testing

  def load_directives(filename, resource)
    # Columns: page, stop-point-for, start-point-for, comment
    process_stream(CSV.open(filename, "r",
                         { :col_sep => "\t",
                           :headers => true,
                           :header_converters => :symbol }),
                resource)
  end

  def process_stream(z, resource)
    # page is a page_id, stop and start are trait resource_pks
    # TBD: Check headers to make sure they contain 'page' 'stop' and 'start'
    # z.shift  ???
    # error unless 'page' in z.headers 
    # error unless 'stop' in z.headers 
    # error unless 'start' in z.headers 
    z.each do |row|
      page_id = Integer(row[:page])
      if row.key?(:stop)
        add_directive(page_id, row[:stop], STOP_TERM, "stop", resource)
      end
      if row.key?(:start)
        add_directive(page_id, row[:start], START_TERM, "start", resource)
      end
    end
  end

  # Utility for testing purposes only:
  # Create a stop or start pseudo-trait on a page, indicating that
  # painting of the trait indicated by trait_id should stop or
  # start at that page.
  # Pred (a URI) indicates whether it's a stop or start.
  def add_directive(page_id, trait_id, pred, tag, resource)
    # Pseudo-trait id unique only within resource
    directive_eol_pk = "R#{resource}-BP#{tag}.#{page_id}.#{trait_id}"
    r = run_query(
      "MATCH (t:Trait {resource_pk: '#{trait_id}'})
             -[:supplier]->(r:Resource {resource_id: #{resource}})
       MERGE (m:MetaData {eol_pk: '#{directive_eol_pk}',
                          predicate: '#{pred}',
                          literal: #{page_id}})
       MERGE (t)-[:metadata]->(m)
       RETURN m.eol_pk")
    if r["data"].length == 0
      STDERR.puts("Failed to add #{tag}(#{page_id},#{trait_id})")
    else
      STDERR.puts("Added #{tag}(#{page_id},#{trait_id})")
    end
  end

  # Load directives specified inline (not from a file)

  def test(resource, page_origin)
    process_stream([{:page => page_origin+2, :start => 'tt_2'},
                    {:page => page_origin+4, :stop => 'tt_2'}],
                   resource)
    show(resource)
  end

  # *** Debugging utility ***
  def show(resource)
    puts "State:"
    # List our private taxa
    r = run_query(
     "MATCH (p:Page {testing: 'yes'})
      OPTIONAL MATCH (p)-[:parent]->(q:Page)
      RETURN p.page_id, q.page_id
      LIMIT 100")
    r["data"].map{|row| puts "Page: #{row}\n"}

    # Show the resource
    r = run_query(
      "MATCH (r:Resource {resource_id: #{resource}})
       RETURN r.resource_id
       LIMIT 100")
    r["data"].map{|row| puts "Resource: #{row}\n"}

    # Show all traits for test resource, with their pages
    r = run_query(
      "MATCH (t:Trait)
             -[:supplier]->(:Resource {resource_id: #{resource}})
       OPTIONAL MATCH (p:Page)-[:trait]->(t)
       RETURN t.eol_pk, t.resource_pk, t.predicate, p.page_id
       LIMIT 100")
    r["data"].map{|row| puts "Trait: #{row}\n"}

    # Show all MetaData nodes
    r = run_query(
        "MATCH (m:MetaData)
               <-[:metadata]-(t:Trait)
               -[:supplier]->(r:Resource {resource_id: #{resource}})
         RETURN t.resource_pk, m.predicate, m.literal
         LIMIT 100")
    r["data"].map{|row| puts "Metadatum: #{row}\n"}

    # Show all inferred trait assertions
    r = run_query(
     "MATCH (p:Page)
            -[:inferred_trait]->(t:Trait)
            -[:supplier]->(:Resource {resource_id: #{resource}}),
            (q:Page)-[:trait]->(t)
      RETURN p.page_id, q.page_id, t.resource_pk, t.predicate
      LIMIT 100")
    r["data"].map{|row| print "Inferred: #{row}\n"}
  end

  # Create sample hierarchy and resource to test with
  def populate(resource, page_origin)

    # Create sample hierarchy
    run_query(
      "MERGE (p1:Page {page_id: #{page_origin+1}, testing: 'yes'})
       MERGE (p2:Page {page_id: #{page_origin+2}, testing: 'yes'})
       MERGE (p3:Page {page_id: #{page_origin+3}, testing: 'yes'})
       MERGE (p4:Page {page_id: #{page_origin+4}, testing: 'yes'})
       MERGE (p5:Page {page_id: #{page_origin+5}, testing: 'yes'})
       MERGE (p2)-[:parent]->(p1)
       MERGE (p3)-[:parent]->(p2)
       MERGE (p4)-[:parent]->(p3)
       MERGE (p5)-[:parent]->(p4)
       // LIMIT")
    # Create resource
    run_query(
      "MERGE (:Resource {resource_id: #{resource}})
      // LIMIT")
    # Create trait to be painted
    r = run_query(
      "MATCH (p2:Page {page_id: #{page_origin+2}}),
             (r:Resource {resource_id: #{resource}})
       MERGE (t2:Trait {eol_pk: 'tt_2_in_this_resource',
                        resource_pk: 'tt_2', 
                        predicate: '#{SILLY_TERM}',
                        literal: 'value of trait'})
       MERGE (p2)-[:trait]->(t2)
       MERGE (t2)-[:supplier]->(r)
       RETURN t2.eol_pk, p2.page_id
       // LIMIT")
    r["data"].map{|row| print "Merged: #{row}\n"}
    show(resource)
  end

  # Doesn't work under new authorization rules.

  def flush(resource)
    # Get rid of the test resource MetaData nodes (and their :metadata
    # relationships)
    run_query(
      "MATCH (m:MetaData)
             <-[:metadata]-(:Trait)
             -[:supplier]->(:Resource {resource_id: #{resource}})
       DETACH DELETE m
       LIMIT 10000")

    # Get rid of the test resource traits (and their :trait,
    # :inferred_trait, and :supplier relationships)
    run_query(
      "MATCH (t:Trait)
             -[:supplier]->(:Resource {resource_id: #{resource}})
       DETACH DELETE t
       LIMIT 10000")

    # Get rid of the resource node itself
    run_query(
      "MATCH (r:Resource {resource_id: #{resource}})
       DETACH DELETE r
       LIMIT 10000")

    # Get rid of taxa introduced for testing purposes
    run_query(
      "MATCH (p:Page {testing: 'yes'})
       DETACH DELETE p
       LIMIT 10000")

    show(resource)

  end

end
