BloomJS
----

A set of bloom filter implementations in pure coffee/javascipt.

----

Currently three bloom filters are supported:

* sliced bloom filter: a bloom filter that is optimized to minimize false positives.
* strict sliced bloom filter: same as above but forbids you from adding more keys than the filter supports.
* scalable bloom filter: a bloom filter than automatically alocates additional space. It grows, while preserving your target error rate.

----

Examples: See the index.html file.
