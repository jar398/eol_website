
namespace :paint do

  pred = "http://example.org/slimy"
  herit = "https://example.org/heritable"
  resource = "test"

  desc 'flush'
  task flush: :environment do
    TraitBank::query(
      "MATCH (p:Page {testing: 'yes'})
       DETACH DELETE p")

    TraitBank::query(
      "MATCH (t:Trait {predicate: '#{pred}'})
       DETACH DELETE t")

    TraitBank::query(
      "MATCH (m:MetaData {predicate: '#{herit}'})
       DETACH DELETE m")
  end

  desc 'init'
  task init: :environment do
    org = 500000000
    TraitBank::query(
     "MERGE (p1:Page {page_id: #{org+1}, testing: 'yes'})<-[:parent]-
            (p2:Page {page_id: #{org+2}, testing: 'yes'})<-[:parent]-
            (p3:Page {page_id: #{org+3}, testing: 'yes'})<-[:parent]-
            (p4:Page {page_id: #{org+4}, testing: 'yes'})<-[:parent]-
            (p5:Page {page_id: #{org+5}, testing: 'yes'})")
    TraitBank::query(
     "MATCH (p2:Page {page_id: #{org+2}})
      MERGE (p2)-[:trait]->
            (t2:Trait {eol_pk: 'tt_2', 
                       predicate: '#{pred}',
                       resource_pk: '#{resource}'})-[:metadata]->
            (m2:MetaData {eol_pk: 'mm_2', predicate: '#{herit}', literal: 'true'})")
    TraitBank::query(
     "MATCH (p4:Page {page_id: #{org+4}})
      MERGE (p4)-[:trait]->
            (t4:Trait {eol_pk: 'tt_4', 
                       predicate: '#{pred},
                       resource_pk: '#{resource}''})-[:metadata]->
            (m4:MetaData {eol_pk: 'mm_4', predicate: '#{herit}', literal: 'stop'})")
  end

  def get_hierarchy
    # The hierarchy: get all pages that are descended from any 
    # page that has a heritable trait.
    r = TraitBank::query(
     "MATCH (p:Page)<-[:parent]-
            (d:Page)-[:parent*1..]->
            (a:Page)-[:trait]->
            (t:Trait {resource_pk: '#{resource}'})-[:metadata]->
            (:MetaData {predicate: '#{herit}'})
      RETURN d.page_id,        // descendant
             p.page_id")

    # Debug
    r["data"].map{|row| print "Child/parent link: #{row}\n"}

    # Index the hierarchy by parent (map parent to list of children)
    children = Hash.new
    for result in r["data"] do
      d_page_id = result[0]
      p_page_id = result[1]
      ch = children[p_page_id]
      if not ch
        ch = Hash.new
        children[p_page_id] = ch
      end
      ch[d_page_id] = true
    end

    # Debug
    print "#{children.length} pages with children\n"
    children.map{|id, childs| print "Children(#{id}) = #{childs}\n"}

    children
  end

  def get_heritable_traits
    # The heritable traits: (compare to previous query)
    r = TraitBank::query(
     "MATCH (p:Page)-[:trait]->
            (t:Trait {resource_pk: '#{resource}'})-[:metadata]->
            (m:MetaData {predicate: '#{herit}'})
      RETURN p.page_id, t.predicate, m.literal, t.eol_pk")
    r["data"]

    # Debug
    r["data"].map{|row|
      page_id = row[0]
      herit = row[2]
      trait_id = row[3]
      print "Heritable #{herit} for trait #{trait_id} page #{page_id}\n"
    }

    # Index traits by page id and predicate (multiple traits per page)
    heritable = Hash.new
    for result in r["data"] do
      page_id = result[0]
      predicate = result[1]
      herit = result[2]
      trait_id = result[3]

      ph = heritable[page_id]
      if not ph
        ph = Hash.new
        heritable[ph] = ch
      end
      ph[predicate] = [trait_id, herit]
    end
      
    # Debug - show all heritable traits for nodes that have them
    for page_id, by_predicate in heritable do
      print "#{page_id}:\n"
      for predicate, stuff in by_predicate
        trait_id = stuff[0]
        herit = stuff[1]
        print "  #{trait_id} #{herit} #{predicate}\n"
      end
    end

    heritable
  end

  desc 'infer'
  task infer: :environment do

    children = get_hierarchy
    heritable = get_heritable_traits

    # We want: descendants of page a, where a has a trait t that is heritable.
    # But, filter out descendants for which t is overridden (by, say, u).

    # How are we going to do this?  We get the relevant part of the
    # hierarchy, and traverse it top down, propagating the heritable
    # traits down to all descendants, but stopping when overridden.

    def propagate
      3
    end

    7

  end

  desc 'show'
  task show: :environment do
    r = TraitBank::query(
     "MATCH (p:Page {testing: 'yes'})
      RETURN p.page_id")
    r["data"].map{|row| print "Page: #{row}\n"}

    r = TraitBank::query(
     "MATCH (t:Trait {predicate: '#{pred}', resource_pk: '#{resource}'})<-[:trait]-(p:Page)
      RETURN t.eol_pk, p.page_id")
    r["data"].map{|row| print "Trait: #{row}\n"}

    r = TraitBank::query(
     "MATCH (m:MetaData {predicate: '#{herit}'})<-[:metadata]-(t:Trait)
      RETURN m.eol_pk, t.eol_pk")
    r["data"].map{|row| print "MetaData: #{row}\n"}

    r = TraitBank::query(
     "MATCH (p:Page)-[:inferred_trait]->(t:Trait)<-[:trait]-(q:Page)
      RETURN p.page_id, t.eol_pk, q.page_id")
    r["data"].map{|row| print "Inferred: #{row}\n"}
  end

  desc 'paint'
  task paint: :environment do
    # TraitBank::query(cql)
    print 'bar\n'
  end

end
