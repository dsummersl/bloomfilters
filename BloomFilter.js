(function() {
  var HashGenerator, SHA1, ScalableBloomFilter, SlicedBloomFilter, StrictSlicedBloomFilter;
  var __hasProp = Object.prototype.hasOwnProperty, __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor; child.__super__ = parent.prototype; return child; };

  SHA1 = require('crypto/sha1').hex_hmac_sha1;

  /*
  # The sliced bloom filter optimizes the filter by partitioning the bit array into a segment
  # that is reserved for each hash function. Note that once the the @count > @capacity the % failure
  # is now > @errorRate!
  #
  # This implementation is derived from 'Scalable Bloom Filters':
  #
  # http://en.wikipedia.org/wiki/Bloom_filter#CITEREFAlmeidaBaqueroPreguicaHutchison2007
  */

  SlicedBloomFilter = (function() {

    function SlicedBloomFilter(capacity, errorRate, slices, count) {
      var cnt, fnc, i, slice, _ref;
      this.capacity = capacity != null ? capacity : 100;
      this.errorRate = errorRate != null ? errorRate : .001;
      this.slices = slices != null ? slices : null;
      this.count = count != null ? count : 0;
      this.bitsPerInt = 32;
      this.totalSize = Math.floor(this.capacity * Math.abs(Math.log(this.errorRate)) / Math.pow(Math.log(2), 2));
      if (this.totalSize < 0) {
        throw "total size is bigger than an int! " + this.totalSize;
      }
      this.numSlices = Math.ceil(Math.log(1 / this.errorRate) / Math.log(2));
      cnt = 0;
      this.allhashes = [];
      while (cnt++ < this.numSlices) {
        fnc = function(cnt, k) {
          var _this = this;
          return function(k) {
            return SHA1("h" + cnt, k);
          };
        };
        this.allhashes.push(new HashGenerator(fnc(cnt)));
      }
      this.sliceLen = Math.ceil(this.totalSize / this.numSlices);
      if (!this.slices) {
        this.slices = [];
        for (i = 0, _ref = this.numSlices - 1; 0 <= _ref ? i <= _ref : i >= _ref; 0 <= _ref ? i++ : i--) {
          slice = [];
          cnt = 0;
          while (cnt < this.sliceLen) {
            slice.push(0);
            cnt += this.bitsPerInt;
          }
          this.slices.push(slice);
        }
      }
      if (this.slices.length !== this.numSlices) {
        throw "numSlices doesn't match slices: " + this.slices.length + " != " + this.numSlices;
      }
      if (this.slices[0].length * this.bitsPerInt < this.sliceLen) {
        throw "sliceLen doesn't match slice lengths: " + this.sliceLen + " !< " + (this.slices[0].length * this.bitsPerInt);
      }
    }

    SlicedBloomFilter.prototype.computeIndexes = function(bit) {
      return [Math.floor(bit / this.bitsPerInt), Math.ceil(bit % this.bitsPerInt)];
    };

    SlicedBloomFilter.prototype.add = function(k) {
      var i, mask, parts, _ref;
      for (i = 0, _ref = this.numSlices - 1; 0 <= _ref ? i <= _ref : i >= _ref; 0 <= _ref ? i++ : i--) {
        parts = this.computeIndexes(this.allhashes[i].getIndex(k, this.sliceLen));
        mask = 1 << parts[1] - 1;
        this.slices[i][parts[0]] = this.slices[i][parts[0]] | mask;
      }
      this.count++;
      return this;
    };

    SlicedBloomFilter.prototype.has = function(k) {
      var allTrue, i, mask, parts, _ref;
      allTrue = true;
      for (i = 0, _ref = this.numSlices - 1; 0 <= _ref ? i <= _ref : i >= _ref; 0 <= _ref ? i++ : i--) {
        parts = this.computeIndexes(this.allhashes[i].getIndex(k, this.sliceLen));
        mask = 1 << parts[1] - 1;
        allTrue = allTrue && (this.slices[i][parts[0]] & mask) !== 0;
      }
      return allTrue;
    };

    return SlicedBloomFilter;

  })();

  /*
  # Strict filter: fail if you attempt to stuff more into it than its configured to handle.
  */

  StrictSlicedBloomFilter = (function() {

    __extends(StrictSlicedBloomFilter, SlicedBloomFilter);

    function StrictSlicedBloomFilter(capacity, errorRate, slices, count) {
      this.capacity = capacity != null ? capacity : 100;
      this.errorRate = errorRate != null ? errorRate : .001;
      this.slices = slices != null ? slices : null;
      this.count = count != null ? count : 0;
      StrictSlicedBloomFilter.__super__.constructor.call(this, this.capacity, this.errorRate, this.slices, this.count);
    }

    StrictSlicedBloomFilter.prototype.has = function(k) {
      return StrictSlicedBloomFilter.__super__.has.call(this, k);
    };

    StrictSlicedBloomFilter.prototype.add = function(k) {
      if (this.count >= this.capacity) {
        throw "count should be <= capacity, no more room: " + this.count + " <=? " + this.capacity;
      }
      return StrictSlicedBloomFilter.__super__.add.call(this, k);
    };

    return StrictSlicedBloomFilter;

  })();

  HashGenerator = (function() {

    function HashGenerator(hashFunction) {
      this.hashFunction = hashFunction;
    }

    HashGenerator.prototype.getIndex = function(key, len) {
      var c, hash, hexCharsNeeded, vec;
      hash = this.hashFunction(key);
      vec = 0;
      if (len > Math.pow(2, 31)) {
        console.log("WARNING: watch out, I think this is too big. Key: '" + key + "' Len: " + len);
      }
      hexCharsNeeded = parseInt(len / 4);
      c = parseInt(hash.slice(0, 8), 16);
      return c % len;
    };

    return HashGenerator;

  })();

  /*
  # A bloom filter that grows automatically.
  # Consists of several SlicedBloomFilter's to ensure that the
  # filter maintains its % error.
  */

  ScalableBloomFilter = (function() {

    function ScalableBloomFilter(startcapacity, errorRate, filters, stages, r, count) {
      this.startcapacity = startcapacity != null ? startcapacity : 100;
      this.errorRate = errorRate != null ? errorRate : .001;
      this.filters = filters != null ? filters : null;
      this.stages = stages != null ? stages : 2;
      this.r = r != null ? r : 0.85;
      this.count = count != null ? count : 0;
      if (!this.filters) {
        this.filters = [new StrictSlicedBloomFilter(this.startcapacity, this.errorRate)];
      }
    }

    ScalableBloomFilter.prototype.add = function(k) {
      var f, _i, _len, _ref;
      _ref = this.filters;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        f = _ref[_i];
        if (f.count < f.capacity) {
          f.add(k);
          return this;
        }
      }
      this.filters.push(new StrictSlicedBloomFilter(this.startcapacity * Math.pow(this.stages, this.filters.length), this.errorRate * Math.pow(this.r, this.filters.length)));
      this.filters[this.filters.length - 1].add(k);
      return this;
    };

    ScalableBloomFilter.prototype.has = function(k) {
      var f, _i, _len, _ref;
      _ref = this.filters;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        f = _ref[_i];
        if (f.has(k)) return true;
      }
      return false;
    };

    return ScalableBloomFilter;

  })();

  module.exports = {
    BloomFilter: SlicedBloomFilter,
    StrictBloomFilter: StrictSlicedBloomFilter,
    ScalableBloomFilter: ScalableBloomFilter
  };

}).call(this);
