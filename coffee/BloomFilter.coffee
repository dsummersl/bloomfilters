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
class SlicedBloomFilter# {{{
  # The number of keys in the filter.
  @count = 0

  # The number of slices within the filter. Type: an array of BitSet objects.
  @slices = null

  @fromJSON: (json) ->
    slices = []
    if json.slicesType == 'ArrayBitSet'
      slices.push(ArrayBitSet.fromJSON(s)) for s in json.slices
    else
      slices.push(ConciseBitSet.fromJSON(s)) for s in json.slices
    return new SlicedBloomFilter(json.capacity,json.errorRate,slices,json.count,json.hashStartChar)

  # Create a new filter.
  #
  # Parameters:
  #   @capacity      = The size that the filter is expected to be.
  #   @errorRate     = The desired error rate of the filter.
  #   @slices        = Underlying slices used by the bloom filter (for
  #                    deserialization)
  #   @count         = The total number of keys in the filter (for
  #                    deserialization)
  #   @hashStartChar = The salt that is fed to the HashGenerator used by this
  #                    filter.
  constructor: (@capacity=100,@errorRate=.001,@slices=null,@count=0,@hashStartChar='h')->
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
    #console.log("num slices = #{@numSlices} - #{@totalSize}")
    # m = M / k
    @sliceLen = Math.ceil(@totalSize / @numSlices)
    @hashgenerator = new HashGenerator(@hashStartChar,@sliceLen)
    if not @slices
      @slicesType = 'ArrayBitSet'
      @slices = []
      @slices.push(new ArrayBitSet(@sliceLen,@bitsPerInt)) for i in [0..@numSlices-1]
    else
      if @slices[0] not instanceof ArrayBitSet
        @slicesType = 'ConciseBitSet'
    throw "numSlices doesn't match slices: #{@slices.length} != #{@numSlices}" if @slices.length != @numSlices
    throw "sliceLen doesn't match slice lengths: #{@sliceLen} !< #{@slices[0].length*@bitsPerInt}" if @slices[0].length*@bitsPerInt < @sliceLen

  add: (k) ->
    @hashgenerator.reset(k)
    for i in [0..@numSlices-1]
      #console.log "setBit #{k} before? #{@has(k)}"
      @slices[i].add(@hashgenerator.getIndex())
      #console.log "setBit #{k} @slices[i][#{parts[0]}] #{parts[1]} = #{@slices[i][parts[0]]} | #{mask} == #{@slices[i][parts[0]]}"
      #console.log "setBit #{k} after? #{@has(k)}"
    @count++
    return this

  has: (k) ->
    @hashgenerator.reset(k)
    for i in [0..@numSlices-1]
      index = @hashgenerator.getIndex()
      #console.log "bitSet? #{k} @slices[#{i}].has(#{index}) ?= #{@slices[i].has(index)}"
      return false if not @slices[i].has(index)
    return true

  # Return a 'read only' instance of this filter. In fact it returns a
  # SlicedBloomFilter with a concise bitset implementation.
  readOnlyInstance: ->
    ROslices = []
    ROslices.push(s.toConciseBitSet()) for s in @slices
    sbf = new SlicedBloomFilter(@capacity,@errorRate,ROslices,@count,@hashStartChar)
    return sbf
# }}}
###
# Strict filter: fail if you attempt to stuff more into it than its configured to handle.
###
class StrictSlicedBloomFilter extends SlicedBloomFilter# {{{
  @fromJSON: (json) ->
    sbl = SlicedBloomFilter.fromJSON(json)
    return new StrictSlicedBloomFilter(sbl.capacity,sbl.errorRate,sbl.slices,sbl.count,sbl.hashStartChar)

  constructor: (@capacity=100,@errorRate=.001,@slices=null,@count=0,@hashStartChar='h') -> super(@capacity,@errorRate,@slices,@count,@hashStartChar)
  add: (k) ->
    throw "count should be <= capacity, no more room: #{@count} <= #{@capacity}" if @count >= @capacity
    super(k)
# }}}
###
# A hash function. It is intended to be used to:
#
# 1: set the key/length of indexes
# 2: fetch several random indexes.
#
# This class automatically handles the hash generation - minimizing the
# total number of hashes generated.
###
class HashGenerator# {{{
  constructor: (@hashStartChar,@len) ->
    @hexCharsNeeded = Math.ceil(Math.log(@len) / Math.log(16))

  ###
  # Anchor the generator on to a specific key. Reset any hash data.
  ###
  reset: (key) ->
    @key = key
    @hashCnt = 0
    @hash = ""
    #console.log "reset"

  # For a target length and key defined by 'reset', get an index (0-based) sized to 'len'.
  getIndex: () ->
    # here I'm trying to generate as few calls to the SHA1 method as possible by
    # just using up the minimum number of hex chars required to generate an index
    # of length @len -- whenever we get to a point that we don't have enough
    # characters to generate an index, only then do we call SHA1 (but we keep what
    # we couldn't use in the last call).
    if @hash == "" or @hashIdx > @hash.length-@hexCharsNeeded
      #console.log "from #{@hashIdx} to #{@hash.length}: #{@hash.slice(@hashIdx,@hash.length)}"
      @hash = SHA1("#{@hashStartChar}-#{@hashCnt}-#{@key}",@key) + @hash.slice(@hashIdx,@hash.length)
      @hashCnt++
      @hashIdx = 0
      #console.log "new hash for key #{@key}: #{@hash} - uses: #{@hash.length / @hexCharsNeeded} #{@hexCharsNeeded}"
    #console.log "."
    console.log("WARNING: watch out, I think this is too big. Key: '#{@key}' Len: #{@len}") if (@len > Math.pow(2,31))
    c = parseInt(@hash.slice(@hashIdx, @hashIdx+@hexCharsNeeded), 16)
    #console.log "#{@key}: #{@hash[@hashIdx-1]}-#{@hash.slice(@hashIdx, @hashIdx+@hexCharsNeeded)}: #{@hexCharsNeeded}-#{@len}-#{@hexCharsNeeded} - #{c} (#{@hexCharsNeeded})"
    @hashIdx += @hexCharsNeeded
    return c
# }}}

###
# Base bit set class (abstract). These bitset implementations are used by the
# bloom filters as underlying storage.
###
class BitSet# {{{
  # Turn a bit # 'b' to the set.
  add: (b) ->
  # Check if bit 'b' is in this set. Returns boolean.
  has: (b) -> false

  # Given a string representation of a binary number, convert it to a number.
  # 
  # Example: Given a string '1000' return 8
  bitStringAsWord: (str) ->
    b = 0
    offset = 31
    for bit in str
      if bit != ' '
        b = b | (parseInt(bit) << offset--)
    return b

  # Given a number, return a string representation of the number in binary form.
  #
  # Example: Given the number 8, return '1000'.
  wordAsBitString: (w) ->
    str = ""
    for i in [31..0]
      str += " " if (i+1) % 4 == 0 and i != 31
      if @bitOfWordSet(w,i)
        str += "1"
      else
        str += "0"
    return str

  # For a word and bit position, return true if the bit defined by the bit
  # position is set to 1.
  #
  # Example: Given a word '1001' and bit position 2 and 3 would return false. Bit
  # position 1 and 4 would return true.
  bitOfWordSet: (w,i) -> (w & (1 << i)) != 0

  # For a word, count the number of bits that are set to one.
  #
  # Example: '1100' would return 2, '1011' returns 3.
  #
  # Note: 32 bit positions of the word are compared.
  bitsOfWordSet: (w) ->
    cnt = 0
    cnt++ for i in [0..31] when @bitOfWordSet(w,i)
    return cnt

  # Compare two words. Returns true if all bits of the two words match.
  #
  # Note: 32 bit positions of the word are compared.
  wordMatches: (w,p) ->
    allMatch = true
    for i in [0..31]
      allMatch = @bitOfWordSet(w,i) == @bitOfWordSet(p,i)
      return false if not allMatch
    return true
# }}}
###
# Straight up array based bit set (well, we use the bits of the ints in the array).
###
class ArrayBitSet extends BitSet # {{{
  @fromJSON: (json) -> return new ArrayBitSet(json.size,json.bitsPerInt,json.data,json.max)
  # size is the number of words of with bitsPerInt in each word...
  constructor: (@size,@bitsPerInt=32,@data=[],@max) ->
    cnt = 0
    while cnt < @size
      @data.push(0)
      cnt += @bitsPerInt

  computeIndexes: (bit) -> [Math.floor(bit / @bitsPerInt), Math.ceil(bit % @bitsPerInt)]
  add: (bit) ->
    throw "Array is setup for #{@size*@bitsPerInt} bits, but bit #{bit} was attempted." if bit >= @size*@bitsPerInt
    parts = @computeIndexes(bit)
    mask = 1 << parts[1]-1
    @data[parts[0]] = (@data[parts[0]] | mask)
    @max = bit if bit > @max
  has: (bit) ->
    return false if bit >= @size*@bitsPerInt
    parts = @computeIndexes(bit)
    mask = 1 << parts[1]-1
    return (@data[parts[0]] & mask) != 0

  toConciseBitSet: ->
    cbs = new ConciseBitSet()
    cnt = 0
    max = 0
    for i in [0..@size*@bitsPerInt]
      if @has(i)
        cnt++
        max = i
        cbs.add(i)
    #console.log "my BS(#{@data.length}) has #{cnt} and the ROBS(#{cbs.words.length} - #{cbs.max}) has #{cbs.count} max is #{max}"
    return cbs

  printObject: ->
    console.log "size = #{@size}"
    console.log "word #{i} : #{@wordAsBitString(w)}" for w,i in @data
# }}}
###
# CONCISE bit set.
# unfortunately you can't use the CONCISE bit for a writeable bloom filter so
# we are just using it for the read only version - for its space saving features.
#
# This bitmap is really only useful if the bloom filter is mostly full, or mostly empty. In that
# middle state, there aren't sparse areas of 1s or 0s for it to compress.
#
# If the # of items in the bloom filter is near the capacity of the filter, the standard array
# is almost always better (uses less space)
###
class ConciseBitSet extends BitSet # {{{
  @fromJSON: (json) -> return new ConciseBitSet(json.words,json.top,json.max,json.count)

  constructor: (@words=[],@top=0,@max=0,@count=0) ->

  add: (i) ->
    #console.log "append #{i}"
    # I think this must be true: i >= @max
    if @words.length == 0 # first append
      f = Math.floor(i/31.0)
      #console.log "length is 0 and f = #{f}"
      switch f
        when 0
          @top = 0
        when 1
          @top = 1
          @setWord(0,0x80000000)
        else # fill
          @top = 1
          @setWord(0,f-1)
      @setWord(@top,(0x80000000 | (1 << (i % 31))))
    else
      b = i - @max + (@max % 31)
      #console.log "b = #{b}"
      if b >= 31
        zeroBlocks = Math.floor(b/31.0) - 1
        b = b % 31 # zeroes are required before we can insert this bit
        #console.log "f = #{zeroBlocks}, b = #{b}"
        @appendSequence(zeroBlocks,0) if zeroBlocks > 0
        #console.log "and literal low end"
        @appendLiteral(0x80000000 | (1 << b))
      else
        @setWord(@top,@words[@top] | (1 << b))
        if @wordMatches(@words[@top],0xffffffff)
          #console.log "appending literal"
          @top = @top - 1
          @words = [] if @top < 0
          @top = 0 if @top < 0
          #console.log "words = #{@words.length} #{@top}"
          @appendLiteral(0xffffffff)
          #console.log "words = #{@words.length} #{@top}"
    @max = i
    @count++

  appendLiteral: (w) ->
    return if @top == 0 && @wordMatches(w,0x80000000) && @wordMatches(@words[0],0x01ffffff)
    if @words.length == 0 # first append
      @top = 0
      @setWord(@top,w)
    else if @wordMatches(w,0x80000000) # all 0's literal
      if @wordMatches(@words[@top],0x80000000)
        #console.log "0x8"
        @setWord(@top,1 ) # sequence of 2 blocks of 0's
      else if (@words[@top] & 0xc0000000) == 0
        #console.log "0xc"
        @setWord(@top,@words[@top] + 1 ) # one more block
      else if @containsOneBit(0x7fffffff & @words[@top])
        #console.log "hasabit"
        # convert the last one-set-bit literal in a mixed word of 2 blocks of 0's
        @setWord(@top,(1 | ((1+@trailingZeros(@words[@top])) << 25)))
      else # nothing to merge
        #console.log "nomerge"
        @top++
        @setWord(@top,w)
    else if @wordMatches(w,0xffffffff) # all 1's literal
      if @wordMatches(@words[@top],0xffffffff)
        @setWord(@top,0x40000000 | 1 ) # sequence of 2 blocks of 1's
      else if @wordMatches((@words[@top] & 0xc0000000),0x40000000)
        @setWord(@top,@words[@top] + 1 ) # one more block
      else if @containsOneBit(~@words[@top])
        # convert the last one-unset-bit literal in a mixed word of 2 blocks of 1's
        @setWord(@top,0x40000000 | 1 | ((1+@trailingZeros(~@words[@top])) << 25))
      else # nothing to merge
        @top++
        @setWord(@top,w)
    else # nothing to merge
      @top++
      @setWord(@top,w)

  appendSequence: (l,t) ->
    t = t & 0x40000000 # retain only the fill type
    if l == 1
      if t == 0
        @appendLiteral(0x80000000)
      else
        @appendLiteral(0xffffffff)
    else if @words.length == 0
      @top = 0
      @setWord(@top,(t | (l-1)))
    else if @isLiteral(@words[@top]) # the last word is a literal
      if t == 0 && @wordMatches(@words[@top],0x80000000)
        @setWord(@top,l ) # make a sequence of l + 1 blocks of 0's
      else if @wordMatches(t,0x40000000) || @wordMatches(@words[@top],0xffffffff)
        @setWord(@top,(0x40000000 | l)) # make a sequence of l+1 blocks of 1's
      else if t==0 && @containsOneBit(0x7fffffff & @words[@top])
        @setWord(@top,(l | ((1 + @trailingZeros(@words[@top])) << 25)))
      else if @wordMatches(t,0x40000000) && @containsOneBit(~@words[@top])
        @setWord(@top,0x40000000 | l | ((1 + @trailingZeros(~@words[@top])) << 25))
      else # nothing to merge
        @top++
        @setWord(@top,(t | (l-1)))
    else if @wordMatches((@words[@top] & 0xc0000000),t)
      @setWord(@top,@words[@top] + l)
    else
      @top++
      @setWord(@top,(t | (l-1)))

  # Set the word at index i (check bounds and such)
  setWord: (i,w) ->
    throw "index i (#{i}) should be no more than 1 more than @words length (currently #{@words.length}" if i > @words.length
    if @words.length < i-1
      @words.push(w)
      #console.log "Set new word[#{i}] = #{@wordAsBitString(w)}"
    else
      #console.log "Replace word[#{i}]: #{@wordAsBitString(@words[i])} -> #{@wordAsBitString(w)}"
      @words[i] = w

  printObject: ->
    console.log "top = #{@top}"
    console.log "max = #{@max}"
    console.log "count = #{@count}"
    for w,i in @words
      console.log "word #{i} : #{@wordAsBitString(w)}" if (i <= @top)

  isLiteral: (w) -> (w & 0x80000000) != 0 #1 literal word
  is01Fill: (w) -> (w & 0x80000000) == 0 && (w & 0x40000000) != 0 #01 fill word
  is00Fill: (w) -> (w & 0x80000000) == 0 && (w & 0x40000000) == 0 #00 fill word

  bitCount: (arr=@words) ->
    cnt = 0
    for w in arr
      if @isLiteral(w)
        #console.log "literal word: #{@wordAsBitString(w)} - count #{@bitsOfWordSet(w)-1}"
        cnt += @bitsOfWordSet(w) - 1
      else if @is01Fill(w)
        #console.log '01 word'
        cnt += 31 + 31*@bitsOfWordSet(w & 0x7ffffff)
        cnt -= @bitsOfWordSet((w >> 25) & 0x1f)
      else if @is00Fill(w)
        #console.log '00 word'
        cnt += @bitsOfWordSet((w >> 25) & 0x1f)
      else
        throw "Should start with 1, or 00 or 01 !?"
    return cnt

  # Does this bitset contain number n?
  has: (n) ->
    return false if n > @max || @words.length == 0 || n < 0
    block = Math.floor(n / 31.0)
    bit = n % 31
    for w in @words
      if @isLiteral(w)
        return (w & (1 << bit)) != 0 if block == 0
        block--
        #console.log "literal bit set? #{@wordAsBitString(w)} for #{n-height} is #{@bitOfWordSet(w,n-height)}"
        ###
        if n - height <= 31
          return @bitOfWordSet(w,n-height)
        height += 31
        ###
      else if @is01Fill(w)
        return false if block == 0 && @wordMatches((0x0000001f & (w >> 25) - 1),bit)
        block -= (w & 0x01FFFFFF) + 1
        return true if block < 0
      else if @is00Fill(w)
        return true if block == 0 && @wordMatches((w >> 25) - 1,bit)
        block -= (w & 0x01FFFFFF) + 1
        return false if block < 0
    return false

  containsOneBit: (w) -> (w & (w-1)) == 0

  trailingZeros: (v) ->
    c = 0
    if v != 0
      foundOne = false
      v = v ^ 0x80000000 # set highest bit to 1, and then just walk down till we find a one.
      while not foundOne
        if (v & 1) == 0
          c++
        else
          foundOne = true
        v >>= 1
    else
      c = 32
    return c
# }}}
###
# A bloom filter that grows automatically.
# Consists of several SlicedBloomFilter's to ensure that the
# filter maintains its % error.
#
# http://en.wikipedia.org/wiki/Bloom_filter#CITEREFAlmeidaBaqueroPreguicaHutchison2007
###
class ScalableBloomFilter# {{{
  @fromJSON: (json) ->
    filters = []
    filters.push(StrictSlicedBloomFilter.fromJSON(f)) for f in json.filters
    return new ScalableBloomFilter(json.startcapacity,json.targetErrorRate,filters,json.stages,json.r,json.count)

  constructor: (@startcapacity=100,@targetErrorRate=.001,@filters=null,@stages=4,@r=0.85,@count=0)->
    # number of stages:
    # 4 is considered good for large growth (4+ orders of magnitude)
    # 2 is considered good for less growth (around 2 orders of magnitude)
    # k_i = k_0 + i*log2(r^-1)
    @P_0 = @targetErrorRate*(1-@r)
    if not @filters
      @filters = [new StrictSlicedBloomFilter(@startcapacity,@P_0,null,0,'h0')]

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
    # also increase:
    #console.log "new cap & rate: #{@startcapacity*Math.pow(@stages,@filters.length)} and #{@P_0*Math.pow(@r,@filters.length)}"
    @filters.push(new StrictSlicedBloomFilter(@startcapacity*Math.pow(@stages,@filters.length),@P_0*Math.pow(@r,@filters.length),null,0,"h#{@filters.length}"))
    @filters[@filters.length-1].add(k)
    return this

  has: (k) ->
    for f in @filters
      return true if f.has(k)
    return false
  
  readOnlyInstance: ->
    ROfilters = []
    ROfilters.push(f.readOnlyInstance()) for f in @filters
    return new ScalableBloomFilter(@startcapacity,@targetErrorRate,ROfilters,@stages,@r,@count)
# }}}

module.exports =
  BloomFilter: SlicedBloomFilter
  StrictBloomFilter: StrictSlicedBloomFilter
  ScalableBloomFilter: ScalableBloomFilter
  ConciseBitSet: ConciseBitSet
  ArrayBitSet: ArrayBitSet

# vim: set fdm=marker:
