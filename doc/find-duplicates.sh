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
[ x$TEMPDIR = x ] && TEMPDIR=/tmp/dup-report

[ x$SERVER = x ] && SERVER=https://eol.org/

function main {
  >&2 echo "Server is $SERVER, temp is $TEMPDIR"
  strictness=$1
  # I had 'clade' here but shell variables seem to be global in bash and 
  # there was a hard-to-debug conflict. 
  # The shell is just an awful awful language for programming in!
  qlade=$2
  properti=$3
  if [ x$strictness = x ]; then
    report strict $qlade $properti
    report lax $qlade $properti
  else
    report $strictness $qlade $properti
  fi
}

# strictness required, clade optional

function report {
  strictness=$1
  clade=$2
  property=$3
  >&2 echo "##### report $strictness $clade #####"
  mkdir -p $TEMPDIR
  if [ x$clade != x ]; then
    if [ x$property != x ]; then
      if [ $property = object_term ]; then
        rel $clade $clade $property $strictness $outfile
      else
        prop $clade $clade $property $strictness $outfile
      fi
    else
      outfile=$TEMPDIR/dups-$clade-$strictness.csv
      cat /dev/null >$outfile
      check_clade $clade $clade $strictness $outfile
    fi
  else
    outfile=$TEMPDIR/dups-$strictness.csv
    cat /dev/null >$outfile
    check_clade   2774383 vertebrates $strictness $outfile
    check_clade      2195 mollusks $strictness $outfile
    check_clade       164 arthropods $strictness $outfile
    check_clade  42430800 plants $strictness $outfile
    check_clade  46702383 fungi $strictness $outfile
    check_clade    106805 bacteria $strictness $outfile
    >&2 echo "Wrote report to $outfile"
  fi
}

# Run all queries for a given clade and strictness

function check_clade {
  clade=$1
  name=$2
  strictness=$3
  outfile=$4
  >&2 echo "##### check_clade $clade $name $strictness $outfile #####"
  prop $clade $name measurement $strictness $outfile
  prop $clade $name object_page_id $strictness $outfile
  rel $clade $name object_term $strictness $outfile
  # Skipping: literal (usually replicates object_term) and normal_measurement
}

function prop {
  clade=$1
  group=$2
  property=$3
  strictness=$4
  outfile=$5
  >&2 echo "##### prop $group $property $strictness #####"
  if [ $strictness = strict ]; then
    foo="t.$property as value,"
    baz="value,"
  else
    foo=""
    baz=""
  fi
  stage=$TEMPDIR/$group-$property-$strictness.csv
  sleep 1
  time python doc/cypher.py --format csv \
    --server $SERVER --tokenfile $TOKENFILE \
    --query "MATCH (a:Page {page_id: $clade})<-[:parent*0..]-
                   (p:Page)-[:trait]->(t:Trait)-[:supplier]->(r:Resource),
                   (t)-[:predicate]->(pred:Term)
             WHERE t.$property IS NOT NULL
             WITH p, pred, $foo
                  COLLECT(DISTINCT r.resource_id) AS resources
             WHERE SIZE(resources) > 1
             WITH '$property' as property,
                  '$group' as group,
                  pred, $baz resources,
                  COLLECT(DISTINCT p.page_id) AS pages
             RETURN pred.name, property, $baz group, resources, 
                    size(pages), pages[0..10]
             ORDER BY pred.name, -SIZE(resources), resources
             LIMIT 50000" \
    >$stage
  if [ x$outfile = x ]; then
    >&2 echo "Wrote to $stage"
  elif [ -s $outfile ]; then
    gtail -n +2 $stage >>$outfile
  else
    cp $stage $outfile
  fi
}

function rel {
  clade=$1
  # 'group' = clade name
  group=$2
  relation=$3
  strictness=$4
  outfile=$5
  >&2 echo "##### rel $group $relation $strictness #####"
  if [ $strictness = strict ]; then
    foo="o,"
    baz="o.name,"
  else
    foo=""
    baz=""
  fi
  stage=$TEMPDIR/$group-$relation-$strictness.csv
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
                  '$group' as group,
                  pred, $foo resources, 
                  COLLECT(p.page_id) AS pages
             RETURN pred.name, relation, $baz group, resources,
                    size(pages), pages[0..10]
             ORDER BY pred.name, -SIZE(resources), resources
             LIMIT 50000" \
    >$stage
  if [ x$outfile = x ]; then
    >&2 echo "Wrote to $stage"
  elif [ -s $outfile ]; then
    gtail -n +2 $stage >>$outfile
  else
    cp $stage $outfile
  fi
}

# main strictness clade property
main "$1" "$2" "$3"
