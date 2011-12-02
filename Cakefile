fs = require 'fs'
exec = require('child_process').exec

task 'test','Run unit tests', (options) ->
  exec 'NODE_PATH="coffee" ./node_modules/.bin/jasmine-node --coffee test/spec', (error,stdout,stderr) ->
    console.log stdout
    console.log stderr
    #console.log error if error != null

task 'js','compile the coffeescript into javascript', (options)->
  exec './node_modules/.bin/coffee coffee -c -o . coffee', (error,stdout,stderr) ->
    console.log stdout
    console.log stderr
    #console.log error if error != null
