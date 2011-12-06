SHA1 = require('crypto/sha1').hex_hmac_sha1

###
# The sliced bloom filter optimizes the filter by partitioning the bit array into a segment
# that is reserved for each hash function. Note that once the the @count > @capacity the % failure
# is now > @errorRate!
#
# This implementation is derived from 'Scalable Bloom Filters':
#
# http://en.wikipedia.org/wiki/Bloom_filter#CITEREFAlmeidaBaqueroPreguicaHutchison2007
###
class SlicedBloomFilter
  constructor: (@capacity=100,@errorRate=.001,@slices=null,@count=0,hashStartChar='h')->
    @bitsPerInt = 32
    # P = p^k = @errorRate
    # n = @capacity
    # p = 1/2
    # M = @totalSize
    # M = n abs(ln P) / (ln2)^2
    @totalSize = Math.floor(@capacity * Math.abs(Math.log(@errorRate)) / Math.pow(Math.log(2),2))
    throw "total size is bigger than an int! #{@totalSize}" if @totalSize < 0
    # k = @slices
    # k = log2(1/P)
    @numSlices = Math.ceil(Math.log(1/@errorRate)/Math.log(2))
    cnt = 0
    @hashgenerator = new HashGenerator(hashStartChar)
    #console.log("num slices = #{@numSlices} - #{@totalSize}")
    # m = M / k
    @sliceLen = Math.ceil(@totalSize / @numSlices)
    if not @slices
      @slices = []
      for i in [0..@numSlices-1]
        slice = []
        cnt = 0
        while cnt < @sliceLen
          slice.push(0)
          cnt += @bitsPerInt
        @slices.push(slice)
    throw "numSlices doesn't match slices: #{@slices.length} != #{@numSlices}" if @slices.length != @numSlices
    throw "sliceLen doesn't match slice lengths: #{@sliceLen} !< #{@slices[0].length*@bitsPerInt}" if @slices[0].length*@bitsPerInt < @sliceLen

  computeIndexes: (bit) -> [Math.floor(bit / @bitsPerInt), Math.ceil(bit % @bitsPerInt)]

  add: (k) ->
    @hashgenerator.reset(k,@sliceLen)
    for i in [0..@numSlices-1]
      parts = @computeIndexes(@hashgenerator.getIndex())
      mask = 1 << parts[1]-1
      #console.log "setBit #{k} before? #{@has(k)}"
      @slices[i][parts[0]] = @slices[i][parts[0]] | mask
      #console.log "setBit #{k} @slices[i][#{parts[0]}] #{parts[1]} = #{@slices[i][parts[0]]} | #{mask} == #{@slices[i][parts[0]]}"
      #console.log "setBit #{k} after? #{@has(k)}"
    @count++
    return this

  has: (k) ->
    @hashgenerator.reset(k,@sliceLen)
    for i in [0..@numSlices-1]
      parts = @computeIndexes(@hashgenerator.getIndex())
      mask = 1 << parts[1]-1
      return false if (@slices[i][parts[0]] & mask) == 0
      #console.log "bitSet? #{k} @slices[#{i}][#{parts[0]}] = #{@slices[i][parts[0]]} & #{mask} = #{(@slices[i][parts[0]] & mask) != 0} of #{@slices[i]}"
    return true

###
# Strict filter: fail if you attempt to stuff more into it than its configured to handle.
###
class StrictSlicedBloomFilter extends SlicedBloomFilter
  constructor: (@capacity=100,@errorRate=.001,@slices=null,@count=0,hashStartChar='h') -> super(@capacity,@errorRate,@slices,@count,hashStartChar)
  has: (k) -> super(k)
  add: (k) ->
    throw "count should be <= capacity, no more room: #{@count} <= #{@capacity}" if @count >= @capacity
    super(k)

###
# A hash function. It is intended to be used to:
#
# 1: set the key/length of indexes
# 2: fetch several random indexes.
#
# This class automatically handles the hash generation - minimizing the
# total number of hashes generated.
###
class HashGenerator
  constructor: (@hashStartChar) ->

  ###
  # Anchor the generator on to a specific key and index length. Reset any hash
  # data.
  ###
  reset: (key,len) ->
    @key = key
    @len = len
    @hashCnt = 0
    @hash = null

  # For a target length and key defined by 'reset', get an index (0-based) sized to 'len'.
  getIndex: () ->
    if not @hash or @hashIdx > @hash.length-8
      @hashCnt++
      @hashIdx = 0
      @hash = SHA1("#{@hashStartChar}-#{@hashCnt}",@key)
      #console.log "new hash for key #{@key}: #{@hash}"
    console.log("WARNING: watch out, I think this is too big. Key: '#{@key}' Len: #{@len}") if (@len > Math.pow(2,31))
    # (2^4)^8
    hexCharsNeeded = parseInt(@len / 4)
    c = parseInt(@hash.slice(@hashIdx, @hashIdx+8), 16)
    #console.log "#{@len}: #{@hash.slice(@hashIdx, @hashIdx+8)} -- #{c} (#{hexCharsNeeded}) - #{@hashIdx} #{@hash.length}"
    @hashIdx += 8
    return c % @len

###
# A bloom filter that grows automatically.
# Consists of several SlicedBloomFilter's to ensure that the
# filter maintains its % error.
#
# http://en.wikipedia.org/wiki/Bloom_filter#CITEREFAlmeidaBaqueroPreguicaHutchison2007
###
class ScalableBloomFilter
  constructor: (@startcapacity=100,@errorRate=.001,@filters=null,@stages=4,@r=0.85,@count=0)->
    # number of stages:
    # 4 is considered good for large growth (4+ orders of magnitude)
    # 2 is considered good for less growth (around 2 orders of magnitude)
    # k_i = k_0 + i*log2(r^-1)
    @count = 0
    if not @filters
      @filters = [new StrictSlicedBloomFilter(@startcapacity,@errorRate,null,0,'h0')]

  add: (k) ->
    @count = 0
    for f in @filters
      @count += f.count
      if f.count < f.capacity
        #console.log "#{f.count} < #{f.capacity} ? #{k}"
        f.add(k)
        @count++
        return this
    @count++
    # None of the previous filters have space left, make a new filter. The new
    # filter will be larger by a factor of @stages, and its errorRatio will
    # also increase...
    #console.log "new cap & rate: #{@startcapacity*Math.pow(@stages,@filters.length)} and #{@errorRate*Math.pow(@r,@filters.length)}"
    @filters.push(new StrictSlicedBloomFilter(@startcapacity*Math.pow(@stages,@filters.length),@errorRate*Math.pow(@r,@filters.length),null,0,"h#{@filters.length}"))
    @filters[@filters.length-1].add(k)
    return this

  has: (k) ->
    for f in @filters
      return true if f.has(k)
    return false

module.exports =
  BloomFilter: SlicedBloomFilter
  StrictBloomFilter: StrictSlicedBloomFilter
  ScalableBloomFilter: ScalableBloomFilter
