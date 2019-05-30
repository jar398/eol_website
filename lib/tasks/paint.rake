
namespace :paint do

  pred = "http://example.org/slimy"
  herit = "https://example.org/heritable"

  def mmmmm(x)
    x
  end

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
     "MATCH (p2:Page {page_id: #{org+2}, testing: 'yes'})
      MERGE (p2)-[:trait]->
            (t2:Trait {eol_pk: 'tt_2', predicate: '#{pred}'})-[:metadata]->
            (m2:MetaData {eol_pk: 'mm_2', predicate: '#{herit}', literal: 'true'})")

    TraitBank::query(
     "MATCH (p4:Page {page_id: #{org+4}, testing: 'yes'})
      MERGE (p4)-[:trait]->
            (t4:Trait {eol_pk: 'tt_4', predicate: '#{pred}'})-[:metadata]->
            (m4:MetaData {eol_pk: 'mm_4', predicate: '#{herit}', literal: 'stop'})")
  end

  desc 'infer'
  task infer: :environment do
    # We want: descendants of page a, where a has a trait t that is heritable.
    # But, filter out descendants for which t is overridden.
    TraitBank::query(
     "MATCH      (m:MetaData {predicate: '#{herit}', value: true})<-[:metadata]-
                 (t:Trait)<-[:trait]-
                 (a:Page)<-[:parent*1..]-(d:Page)
      WHERE NOT ((u:Trait {predicate: t.predicate})<-[:trait]-
                 (i:Page)-[:parent*1..]->(a)
                 AND
                 (i)<-[:parent*1..]-(d) )
      CREATE (d)-[:inferred_trait]->(t)")
  end

  desc 'show'
  task show: :environment do
    r = TraitBank::query(
     "MATCH (p:Page {testing: 'yes'})
      RETURN p.page_id")
    r["data"].map{|row| print "Page: #{row}\n"}

    r = TraitBank::query(
     "MATCH (t:Trait {predicate: '#{pred}'})<-[:trait]-(p:Page)
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
