# rake paint:init
# rake paint:test
# rake paint:infer


require 'csv'

namespace :paint do

  @pred = "http://example.org/numlegs"
  @start = "https://example.org/start-page"
  @stop = "https://example.org/stop-page"
  @resource_id = 99999

  page_origin = 500000000

  desc 'load'
  task load: :environment do
    # Open file paint.tsv ... TBD: make the file name a parameter
    # Columns: page, stop-point-for, start-point-for, comment, provenance ...

    # (wait the provenance is going to be the same as for the trait, right?)
    # store this information somewhere... I guess as fake Traits ??
    # (doesn't make sense for a trait to have provenance.  It's
    # the :trait relationship that would have provenance.)
    # 'page P is a start node for trait T'

    filename = "paint.tsv"
    process_csv(CSV.open(filename, "r",
                         { :col_sep => "\t",
                           :headers => true,
                           :header_converters => :symbol }))
  end

  def process_csv(z)
    # page is a page_id, stop and start are trait resource_ids
    # TBD: Check headers to make sure they contain 'page' 'stop' and 'start'
    # z.shift  ???
    # error unless 'page' in z.headers 
    # error unless 'stop' in z.headers 
    # error unless 'start' in z.headers 

    z.each do |row|
      page_id = Integer(row[:page])
      if row.key?(:stop)
        add_directive(page_id, row[:stop], @stop, "stop")
      end
      if row.key?(:start)
        add_directive(page_id, row[:start], @start, "start")
      end
    end
  end

  # Create a stop or start pseudo-trait on a page, indicating that
  # painting of the trait indicated by trait_id should stop or
  # start at that page.
  # Pred (a URI) indicates whether it's a stop or start.
  def add_directive(page_id, trait_id, pred, tag)
    # Pseudo-trait id unique only within resource
    directive_eol_pk = "R#{@resource_id}-BP#{tag}.#{page_id}.#{trait_id}"
    r = TraitBank::query(
      "MATCH (t:Trait {resource_pk: '#{trait_id}'})
             -[:supplier]->(r:Resource {resource_id: #{@resource_id}})
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

  # Do the painting.
  # Another way to do this would be to just paint directly from the
  # CSV file.  The problem with that is that a change to the DH would
  # require redoing all paintings for all resources - and how would
  # that be driven?  Where would the stop and start points be found?

  desc 'infer'
  task infer: :environment do

    # Propagate traits from start point to descendants.  Filter by resource.
    r = TraitBank::query(
         "MATCH (m:MetaData {predicate: '#{@start}'})
                <-[:metadata]-(t:Trait)
                -[:supplier]->(r:Resource {resource_id: #{@resource_id}}),
                (q:Page)-[:parent*0..]->(p:Page {page_id: m.literal})
          MERGE (q)-[:inferred_trait]->(t)
          RETURN q.page_id, t.eol_pk")
    r["data"].map{|row| puts "Inferred via start directive: #{row}"}

    # Erase inferred traits from stop point to descendants.
    r = TraitBank::query(
         "MATCH (m:MetaData {predicate: '#{@stop}'})
                <-[:metadata]-(t:Trait)
                -[:supplier]->(r:Resource {resource_id: #{@resource_id}}),
                (q:Page)-[:parent*0..]->(p:Page {page_id: m.literal}),
                (q)-[:parent*0..]->(p:Page {page_id: m.literal}),
                (q)-[i:inferred_trait]->(t)
          DELETE i
          RETURN q.page_id, t.eol_pk")
    r["data"].map{|row| puts "Retracted via stop directive: #{row}"}

  end

  desc 'test'
  task test: :environment do
    process_csv([{:page => page_origin+2, :start => 'tt_2'},
                 {:page => page_origin+4, :stop => 'tt_2'}])
    show
  end

  # *** Debugging utility ***
  desc 'show'
  task show: :environment do
    show
  end

  def show
    puts "State:"
    # List our private taxa
    r = TraitBank::query(
     "MATCH (p:Page {testing: 'yes'})
      OPTIONAL MATCH (p)-[:parent]->(q:Page)
      RETURN p.page_id, q.page_id")
    r["data"].map{|row| puts "Page: #{row}\n"}

    # Show the resource
    r = TraitBank::query(
      "MATCH (r:Resource {resource_id: #{@resource_id}})
       RETURN r.resource_id")
    r["data"].map{|row| puts "Resource: #{row}\n"}

    # Show all traits for test resource, with their pages
    r = TraitBank::query(
      "MATCH (t:Trait)
             -[:supplier]->(:Resource {resource_id: #{@resource_id}})
       OPTIONAL MATCH (p:Page)-[:trait]->(t)
       RETURN t.eol_pk, t.resource_pk, t.predicate, p.page_id")
    r["data"].map{|row| puts "Trait: #{row}\n"}

    # Show all MetaData nodes
    r = TraitBank::query(
        "MATCH (m:MetaData)
               <-[:metadata]-(t:Trait)
               -[:supplier]->(r:Resource {resource_id: #{@resource_id}})
         RETURN t.resource_pk, m.predicate, m.literal")
    r["data"].map{|row| puts "Metadatum: #{row}\n"}

    # Show all inferred trait assertions
    r = TraitBank::query(
     "MATCH (p:Page)
            -[:inferred_trait]->(t:Trait)
            -[:supplier]->(:Resource {resource_id: #{@resource_id}}),
            (q:Page)-[:trait]->(t)
      RETURN p.page_id, q.page_id, t.resource_pk, t.predicate")
    r["data"].map{|row| print "Inferred: #{row}\n"}
  end

  # Create sample hierarchy and resource to test with
  desc 'init'
  task init: :environment do
    # Create sample hierarchy
    TraitBank::query(
      "MERGE (p1:Page {page_id: #{page_origin+1}, testing: 'yes'})
       MERGE (p2:Page {page_id: #{page_origin+2}, testing: 'yes'})
       MERGE (p3:Page {page_id: #{page_origin+3}, testing: 'yes'})
       MERGE (p4:Page {page_id: #{page_origin+4}, testing: 'yes'})
       MERGE (p5:Page {page_id: #{page_origin+5}, testing: 'yes'})
       MERGE (p2)-[:parent]->(p1)
       MERGE (p3)-[:parent]->(p2)
       MERGE (p4)-[:parent]->(p3)
       MERGE (p5)-[:parent]->(p4)")
    # Create resource
    TraitBank::query(
      "MERGE (:Resource {resource_id: #{@resource_id}})")
    # Create trait to be painted
    r = TraitBank::query(
      "MATCH (p2:Page {page_id: #{page_origin+2}}),
             (r:Resource {resource_id: #{@resource_id}})
       MERGE (t2:Trait {eol_pk: 'tt_2_in_this_resource',
                        resource_pk: 'tt_2', 
                        predicate: '#{@pred}',
                        literal: 'value of trait'})
       MERGE (p2)-[:trait]->(t2)
       MERGE (t2)-[:supplier]->(r)
       RETURN t2.eol_pk, p2.page_id")
    r["data"].map{|row| print "Merged: #{row}\n"}
    show
  end

  desc 'flush'
  task flush: :environment do

    # Get rid of the test resource MetaData nodes (and their :metadata
    # relationships)
    TraitBank::query(
      "MATCH (m:MetaData)
             <-[:metadata]-(:Trait)
             -[:supplier]->(:Resource {resource_id: #{@resource_id}})
       DETACH DELETE m")

    # Get rid of the test resource traits (and their :trait,
    # :inferred_trait, and :supplier relationships)
    TraitBank::query(
      "MATCH (t:Trait)
             -[:supplier]->(:Resource {resource_id: #{@resource_id}})
       DETACH DELETE t")

    # Get rid of the resource node itself
    TraitBank::query(
      "MATCH (r:Resource {resource_id: #{@resource_id}})
       DETACH DELETE r")

    # Get rid of taxa introduced for testing purposes
    TraitBank::query(
      "MATCH (p:Page {testing: 'yes'})
       DETACH DELETE p")

    show

  end

end
