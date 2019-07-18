#!/bin/bash

# Usage: doc/find-duplicates.sh 
#    or: doc/find-duplicates.sh strictness clade
#   e.g. doc/find-duplicates.sh strict 1642

# Report on duplicate trait records in EOL.
# For testing, try clade 7662 (carnivora) or 1642 (mammals).

set -e

# Change TOKENFILE to point to the file containing your API token.
[ x$TOKENFILE = x ] && TOKENFILE=~/Sync/eol/api.token

# Change TEMPDIR to a scratch directory for use here.
#  E.g. /tmp/dup-report would work
[ x$TEMPDIR = x ] && TEMPDIR=~/eol/dup-report

[ x$SERVER = x ] && SERVER=https://eol.org/

function main {
  strictness=$1
  # I had 'clade' here but shell variables seem to be global in bash and 
  # there was a hard-to-debug conflict. 
  qlade=$2
  if [ x$strictness = x ]; then
    report strict $qlade 
    report lax $qlade 
  else
    report $strictness $qlade 
  fi
}

# strictness required, clade optional

function report {
  strictness=$1
  clade=$2
  >&2 echo "##### report $strictness $clade #####"

  outfile=$TEMPDIR/dups-$strictness.csv
  mkdir -p $TEMPDIR
  cat /dev/null >$outfile
  if [ x$clade != x ]; then
    check_clade $clade $clade $strictness $outfile
  else
    check_clade   2774383 vertebrates $strictness $outfile
    check_clade      2195 mollusks $strictness $outfile
    check_clade       164 arthropods $strictness $outfile
    check_clade  42430800 plants $strictness $outfile
    check_clade  46702383 fungi $strictness $outfile
  fi
  >&2 echo "Wrote report to $outfile"
}

# Run all queries for a given clade and strictness

function check_clade {
  clade=$1
  name=$2
  strictness=$3
  outfile=$4
  >&2 echo "##### check_clade $clade $name $strictness $outfile #####"
  prop $clade $name measurement $strictness $outfile
  prop $clade $name normal_measurement $strictness $outfile
  prop $clade $name literal $strictness $outfile
  prop $clade $name object_page_id $strictness $outfile
  rel $clade $name object_term $strictness $outfile
}

function prop {
  clade=$1
  name=$2
  property=$3
  strictness=$4
  outfile=$5
  >&2 echo "##### prop $name $property $strictness #####"
  if [ $strictness = strict ]; then
    bar="t.$property as value,"
    foo="value,"
  else
    bar=""
    foo=""
  fi
  stage=$TEMPDIR/$name-$property-$strictness.csv
  sleep 1
  time python doc/cypher.py --format csv \
    --server $SERVER --tokenfile $TOKENFILE \
    --query "MATCH (a:Page {page_id: $clade})<-[:parent*0..]-
                   (p:Page)-[:trait]->(t:Trait)-[:supplier]->(r:Resource),
                   (t)-[:predicate]->(pred:Term)
             WHERE t.$property IS NOT NULL
             WITH p, pred, $bar
                  COLLECT(DISTINCT r.resource_id) AS resources
             WHERE SIZE(resources) > 1
             WITH '$property' as property,
                  '$name' as group,
                  pred, $foo resources,
                  COLLECT(DISTINCT p.page_id) AS pages
             RETURN DISTINCT pred.name, property, group, resources, pages
             ORDER BY pred.name, -SIZE(resources), resources
             LIMIT 10000" \
    >$stage
  if [ -s $outfile ]; then
    gtail -n +2 $stage >>$outfile
  else
    cp $stage $outfile
  fi
}

function rel {
  clade=$1
  name=$2
  relation=$3
  strictness=$4
  outfile=$5
  >&2 echo "##### rel $name $relation $strictness #####"
  if [ $strictness = strict ]; then
    foo="o,"
  else
    foo=""
  fi
  stage=$TEMPDIR/$name-$relation-$strictness.csv
  sleep 1
  time python doc/cypher.py --format csv \
    --server $SERVER --tokenfile $TOKENFILE \
    --query "MATCH (a:Page {page_id: $clade})<-[:parent*0..]-
                   (p:Page)-[:trait]->(t:Trait)-[:supplier]->(r:Resource),
                   (t)-[:predicate]->(pred:Term),
                   (t)-[:$relation]->(o:Term)
             WITH p, pred, $foo
                  COLLECT(DISTINCT r.resource_id) AS resources
             WHERE size(resources) > 1
             WITH '$relation' as relation,
                  '$name' as group,
                  pred, $foo resources, 
                  COLLECT(DISTINCT p.page_id) AS pages
             RETURN DISTINCT pred.name, relation, group, resources, pages
             ORDER BY pred.name, -SIZE(resources), resources
             LIMIT 10000" \
    >$stage
  if [ -s $outfile ]; then
    gtail -n +2 $stage >>$outfile
  else
    cp $stage $outfile
  fi
}

# main strictness clade
main $1 $2 
