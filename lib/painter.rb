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
    when "init" then
      painter.populate(resource, @page_origin)
    when "test" then            # Add some directives
      painter.test(resource, @page_origin)
    when "load" then
      filename = get_directives_filename
      painter.load_directives(filename, resource)
    when "show" then
      painter.show(resource)
    when "flush" then
      painter.flush(resource)
    else
      STDERR.puts "Unrecognized command: #{command}"
    end
  end

  def initialize(query_fn)
    @query_fn = query_fn
  end

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
    # Propagate traits from start point to descendants.  Filter by resource.
    query = 
         "MATCH (r:Resource {resource_id: #{resource}})<-[:supplier]-
                (t:Trait)-[:metadata]->
                (m:MetaData)-[:predicate]->
                (:Term {uri: '#{START_TERM}'})
          WITH t, toInteger(m.measurement) as ancestor
          MATCH (a:Page {page_id: ancestor})
                <-[:parent*0..]-(d:Page)
          #{merge}
          RETURN t.eol_pk, d.page_id, ancestor, a.canonical
          LIMIT 10"
    puts query

    r = run_query(query)
    return unless r
    r["data"].map{|row| puts "Inferred via start directive: #{row}"}

    # Erase inferred traits from stop point to descendants.
    r = run_query(
         "MATCH (r:Resource {resource_id: #{resource}})<-[:supplier]-
                (t:Trait)-[:metadata]->
                (m:MetaData)-[:predicate]->
                (:Term {uri: '#{STOP_TERM}'}),
                (a:Page {page_id: m.measurement})-[:parent*0..]->
                (d:Page)
                #{delete}
          RETURN d.page_id, t.eol_pk
          LIMIT 10000")
    r["data"].map{|row| puts "Retracted via stop directive: #{row}"}

    # show(resource)
  end

  # Everything else here is for debugging.

  def get_directives_filename
    # Choose the resource
    if ENV.key?("DIRECTIVES")
      Integer(ENV["DIRECTIVES"])
    else
      @silly_file
    end
  end

  # Load directives from TSV file

  def load_directives(filename, resource)
    # Columns: page, stop-point-for, start-point-for, comment
    process_csv(CSV.open(filename, "r",
                         { :col_sep => "\t",
                           :headers => true,
                           :header_converters => :symbol }),
                resource)
  end

  def process_csv(z, resource)
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
      puts "Failed to add #{tag}(#{page_id},#{trait_id})"
    else
      puts "Added #{tag}(#{page_id},#{trait_id})"
    end
  end

  # Load directives specified inline (not from a file)

  def test(resource, page_origin)
    process_csv([{:page => page_origin+2, :start => 'tt_2'},
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
