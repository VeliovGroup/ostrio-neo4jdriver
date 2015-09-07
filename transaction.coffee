###
@locus Server
@summary Implementation of Transactional Cypher HTTP endpoint
         Event-driven and chainable
         Have to be finished by calling `.commit()` method
@class Neo4jTransaction
@url http://neo4j.com/docs/2.2.5/rest-api-transactional.html
###
class Neo4jTransaction
  __proto__: events.EventEmitter.prototype
  constructor: (@_db, settings, opts = {}) ->
    events.EventEmitter.call @
    @_ready = false
    @_results = []

    @on 'commit', (statement, callback) =>
      if @_ready then @__commit statement, callback else @once 'ready', => @__commit statement, callback
      return

    @on 'execute', (statement, fut) =>
      if @_ready then @__execute statement, fut else @once 'ready', => @__execute statement, fut
      return

    @on 'resetTimeout', (fut) =>
      if @_ready then @__resetTimeout fut else @once 'ready', => @__resetTimeout fut
      return

    @on 'rollback', (fut) =>
      if @_ready then @__rollback fut else @once 'ready', => @__rollback fut
      return

    @on 'ready', (cb) => cb null, true

    statement = @__prepare(settings, opts).request if settings
    statement = [] unless statement

    Meteor.wrapAsync((cb) =>
      @_db.__call @_db.__service.transaction.endpoint, data: statements: statement, 'POST', (error, response) =>
        @__proceedResults error, response, 
        @_commitURL = response.data.commit
        @_execURL = response.data.commit.replace '/commit', ''
        @_expiresAt = response.data.transaction.expires
        @_ready = true
        @emit 'ready', cb
    )()

  __prepare: (settings, opts = {}) ->
    {opts, cypher, resultDataContents, reactive} = @_db.__parseSettings settings, opts
    console.log {opts, cypher, resultDataContents, reactive}

    fill = (cs) ->
      statement: cs
      parameters: opts
      resultDataContents: resultDataContents
      
    statements = request: [], reactive: reactive
    if _.isArray cypher
      statements.request.push fill cypherString for cypherString in cypher
    else if _.isString cypher
      statements.request.push fill cypher
    return statements

  __execute: (statement, fut) ->
    @_db.__call @_execURL, data: statements: statement.request, 'POST', (error, response) =>
      @__proceedResults error, response, statement.reactive
      fut.return @
    return

  __commit: (statement, callback) ->
    data = data: statements: statement.request if statement
    @_db.__call @_commitURL, data, 'POST', (error, response) => 
      @__proceedResults error, response, statement.reactive if statement
      callback null, @_results
      return

  __resetTimeout: (fut) ->
    @_db.__call @_execURL, data: statements: [], 'POST', (error, response) => 
      @_expiresAt = response.data.transaction.expires
      fut.return @
    return

  __rollback: (fut) ->
    @_db.__call @_execURL, null, 'DELETE', => 
      @_results = []
      fut.return undefined
    return

  __proceedResults: (error, response, reactive = false) ->
    unless error
      @_db.__cleanUpResponse response, (result) => 
        @_results.push new Neo4jCursor @_db.__transformData result, reactive
    else
      console.error error
      console.trace()

  ###
  @locus Server
  @summary Reset transaction timeout of an open Neo4j Transaction
  @name rollback
  @class Neo4jTransaction
  @url http://neo4j.com/docs/2.2.5/rest-api-transactional.html#rest-api-rollback-an-open-transaction
  @returns {undefined}
  ###
  rollback: ->
    fut = new Future()
    @emit 'rollback', fut
    return fut.wait()

  ###
  @locus Server
  @summary Reset transaction timeout of an open Neo4j Transaction
  @name resetTimeout
  @class Neo4jTransaction
  @url http://neo4j.com/docs/2.2.5/rest-api-transactional.html#rest-api-reset-transaction-timeout-of-an-open-transaction
  @returns Neo4jTransaction
  ###
  resetTimeout: ->
    fut = new Future()
    @emit 'resetTimeout', fut
    return fut.wait()

  ###
  @locus Server
  @summary Execute statement in open Neo4j Transaction
  @name execute
  @class Neo4jTransaction
  @url http://neo4j.com/docs/2.2.5/rest-api-transactional.html#rest-api-execute-statements-in-an-open-transaction
  @param {Object | String | [String]} settings - Cypher query as String or Array of Cypher queries or object of settings
  @param {String | [String]} settings.cypher - Cypher query(ies), alias: `settings.query`
  @param {Object} settings.opts - Map of cypher query(ies) parameters, aliases: `settings.parameters`, `settings.params`
  @param {[String]} settings.resultDataContents - Array of contents to return from Neo4j, like: 'REST', 'row', 'graph'. Default: `['REST']`
  @param {Boolean} settings.reactive - Reactive nodes updates on Neo4jCursor.fetch(). Default: `false`. Alias: `reactiveNodes`
  @param {Object} opts - Map of cypher query(ies) parameters
  @returns Neo4jTransaction
  ###
  execute: (settings, opts = {}) ->
    fut = new Future()
    @emit 'execute', @__prepare(settings, opts), fut
    return fut.wait()

  ###
  @locus Server
  @summary Commit Neo4j Transaction
  @name commit
  @class Neo4jTransaction
  @url http://neo4j.com/docs/2.2.5/rest-api-transactional.html#rest-api-commit-an-open-transaction
  @param {Object | String | [String]} settings - Cypher query as String or Array of Cypher queries or object of settings
  @param {String | [String]} settings.cypher - Cypher query(ies), alias: `settings.query`
  @param {Object} settings.opts - Map of cypher query(ies) parameters, aliases: `settings.parameters`, `settings.params`
  @param {[String]} settings.resultDataContents - Array of contents to return from Neo4j, like: 'REST', 'row', 'graph'. Default: `['REST']`
  @param {Boolean} settings.reactive - Reactive nodes updates on Neo4jCursor.fetch(). Default: `false`. Alias: `reactiveNodes`
  @param {Function} settings.callback - Callback function. If passed, the method runs asynchronously, instead of synchronously, and calls asyncCallback. Alias: `settings.cb`
  @param {Object} opts - Map of cypher query(ies) parameters
  @param {Function} callback - Callback function. If passed, the method runs asynchronously, instead of synchronously, and calls asyncCallback.
  @returns {[Object]} - Array of Neo4jCursor(s)
  ###
  commit: (settings, opts = {}, callback) ->
    statement = @__prepare(settings, opts) if settings

    unless callback
      return Meteor.wrapAsync((cb) =>
        @emit 'commit', statement, cb
      )()
    else
      @emit 'commit', statement, callback
      return

  ###
  @locus Server
  @summary Get current data in Neo4j Transaction
  @name current
  @class Neo4jTransaction
  @returns {[Object]} - Array of Neo4jCursor(s)
  ###
  current: () -> @_results

  ###
  @locus Server
  @summary Get last received data in Neo4j Transaction
  @name last
  @class Neo4jTransaction
  @returns {Object | null} - Neo4jCursor(s)
  ###
  last: () -> if @_results.length > 0 then @_results[@_results.length - 1] else null