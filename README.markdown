[![build status](https://secure.travis-ci.org/dsummersl/bloomfilters.png)](http://travis-ci.org/dsummersl/bloomfilters)
BloomFilters
----

A set of bloom filter implementations in pure coffee/javascipt.

----

Currently three bloom filters are supported:

* sliced bloom filter: a bloom filter that is optimized to minimize false positives.
* strict sliced bloom filter: same as above but forbids you from adding more keys than the filter supports.
* scalable bloom filter: a bloom filter than automatically alocates additional space. It grows, while preserving your target error rate.
* CONCISE bit map: an implementation of the CONCISE bitmap [http://ricerca.mat.uniroma3.it/users/colanton/concise.html].

----

*Artifacts*

* coffee/BloomFilter.coffee - The primary implementation, in coffeescript.
* js/BloomFilter.js - The node.js friendly version (has require statements - this is what you get if you require this via commonJS).
* stitched.js - A javascript version stitched together with its requirements so you can use this package outside commonJS/Node.
* index.html - a demonstration of the three types of filter.

----

*Development*

You can use the 'cake' command to build this project.

* cake test - test against jasmine test cases.
* cake js - generate all javascript versions.
* cake server - run a test server to view index.html.
