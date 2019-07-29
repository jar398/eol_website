# Finding duplicate trait records in EOL

## Motivation

Trait information is sometimes copied from one source to another,
leading to multiple records in EOL that essentially say the same
thing.

For example, the 'weaning age' of the spiny mouse 
([Acomys cahirinus](https://eol.org/pages/1037942/data))
is recorded as 14 days by two EOL trait records.  One comes from the
[AnAge](http://genomics.senescence.info/species/entry.php?species=Acomys_cahirinus)
web site and the other is from the Pantheria data set ([EA
E090-184-D1](http://esapubs.org/archive/ecol/E090/184/); article is
Jones et al, Ecology 90:2648).  Because there are other species with
the same pair of sources with identical values for various traits, it
seems likely that the origin of the information in the two sources is
the same in each instance.  (This is not always the case of course.)

Cases where the same variable is recorded with different values are
also of interest for data cleaning and data quality purposes.

## Finding traits

The queries I tried did not run to completion in less than a minute,
so I have restricted the search to individual clades.  In the
following I'm considering only mammals (EOL 1642), which have
relatively rich trait information.

Trait values are stored in the graph database under various
properties: `measurement`, `normalized_measurement`, `value`, and
`literal`.

To start with, the following query picks out the page, predicate, and
value of a trait record, and the resource that provides it, in the
situation where the value is stored under the `normal_measurement`
property:

```
    MATCH (a:Page {page_id: 1642})<-[:parent*0..]-
          (p:Page)-[:trait]->(t:Trait)-[:supplier]->(r:Resource),
          (t)-[:predicate]->(pred:Term)
    WHERE t.normal_measurement IS NOT NULL
    RETURN p.page_id, pred.name, t.normal_measurement, r.resource_id
    LIMIT 20
```

Trait records could have the same page, predicate, and value and still
differ significantly by metadata, which could give qualifying
conditions such as life stage.  My guess is that this situation is
rare.

## Finding duplicate traits

By taking the previous result and collecting together rows that differ
only in resource, then filtering by number of resources, we can find
duplicate records:

    MATCH (a:Page {page_id: 1642})<-[:parent*0..]-
          (p:Page)-[:trait]->(t:Trait)-[:supplier]->(r:Resource),
          (t)-[:predicate]->(pred:Term)
    WHERE t.normal_measurement IS NOT NULL
    WITH p, pred, t.normal_measurement AS value, COLLECT(DISTINCT r.resource_id) AS resources
    WHERE SIZE(resources) > 1
    RETURN p.page_id, pred.name, value, resources
    LIMIT 20

This gives a crude list of possible trait record duplicates.  Each row
has the page, predicate, value, and a list of resources providing
trait records that match these properties.

Cypher's `WITH` clause is tremendously useful.

## Finding trait records that cover the same predicate (variable)

By removing the value (`t.normal_measurement` in this case) from the
processing pipeline we get a superset of results that includes cases
where different resources record values the same predicate bur
disagree on what the value is.

    MATCH (a:Page {page_id: 1642})<-[:parent*0..]-
          (p:Page)-[:trait]->(t:Trait)-[:supplier]->(r:Resource),
          (t)-[:predicate]->(pred:Term)
    WHERE t.normal_measurement IS NOT NULL
    WITH p, pred, COLLECT(DISTINCT r.resource_id) AS resources
    WHERE SIZE(resources) > 1
    RETURN p.page_id, pred.name, resources
    LIMIT 20


## Summarizing patterns of trait duplication

As it happens, there are often many pages that follow the same pattern
of duplication, because sources such as AnAge often provide trait
records for many different taxa (pages).  It is useful to summarize these.

    MATCH (a:Page {page_id: 1642})<-[:parent*0..]-
          (p:Page)-[:trait]->(t:Trait)-[:supplier]->(r:Resource),
          (t)-[:predicate]->(pred:Term)
    WHERE t.normal_measurement IS NOT NULL
    WITH p, pred, t.normal_measurement AS value, COLLECT(DISTINCT r.resource_id) AS resources
    WHERE SIZE(resources) > 1
    WITH pred, value, resources,
         COLLECT(DISTINCT p.page_id) AS pages
    RETURN DISTINCT pred.name, value, resources, pages
    LIMIT 20

For each predicate this creates a separate row for each value, showing
the set of pages for each value.  By omitting `value` from the second
`WITH` the page sets can be combined so that there is only one row per
predicate.  Countless variations are possible on the final table
depending on what you'd like to see.

After the final `RETURN` I also like to add an ordering:

    ORDER BY pred.name, -SIZE(resources), resources

which puts rows with the same predicate and resource list near one
another.

## Generating a report

To get the big picture, we want to perform this analysis for many
different taxa and the various properties under which the value is
stored (`measurement`, `literal`, `object_page_id`).

A variation on the query is required when the value is stored
under a relation (`:object_term`) instead of a property.

These is an [uninteresting shell script](find-duplicates.sh) that
creates all of these query variants and compiles the results into two
summary files.
