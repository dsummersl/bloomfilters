fs = require 'fs'
exec = require('child_process').exec

task 'test','Run unit tests', (options) ->
  exec 'NODE_PATH="coffee" ./node_modules/.bin/jasmine-node --coffee test/spec', (error,stdout,stderr) ->
    console.log stdout
    console.log stderr
    #console.log error if error != null

task 'js','compile the coffeescript into javascript', (options)->
  exec "rm -rf #{__dirname}/vendor #{__dirname}/js #{__dirname}/stitched.js"
  exec "#{__dirname}/node_modules/.bin/coffee -b -c -o #{__dirname}/js #{__dirname}/coffee"
  exec "mkdir #{__dirname}/vendor"
  exec "cp -r #{__dirname}/node_modules/crypto #{__dirname}/vendor"

task 'stitch','Make an js file with bloom filter and its dependencies',(o) ->
  stitch = require 'stitch'
  package = stitch.createPackage({ paths: [__dirname+'/js',__dirname+'/vendor'] })
  package.compile( (err,src)->
    fs.writeFile('stitched.js',src,(err)->
      throw err if err
      console.log('Compiled stitched.js')
    )
  )

task 'server','compile and run a test server on port 3000', (options)->
  connect = require 'connect'
  server = connect.createServer(
    connect.favicon(),
    connect.logger(),
    connect.static(__dirname)
  ).listen(3000)
