_ = require 'underscore-plus'
fs = require 'fs-plus'
EmitterMixin = require('emissary').Emitter
{Emitter} = require 'event-kit'
CSON = require 'season'
path = require 'path'
async = require 'async'
pathWatcher = require 'pathwatcher'
{deprecate} = require 'grim'

# Essential: Used to access all of Atom's configuration details.
#
# An instance of this class is always available as the `atom.config` global.
#
# ## Getting and setting config settings. Note that with no value set, {::get}
# returns the setting's default value.
#
# ```coffee
# atom.config.get('my-package.myKey') # -> 'defaultValue'
#
# atom.config.set('my-package.myKey', 'value')
# atom.config.get('my-package.myKey') # -> 'value'
# ```
#
# You may want to watch for changes. Use {::observe} to catch changes to the setting.
#
# ```coffee
# atom.config.set('my-package.myKey', 'value')
# atom.config.observe 'my-package.myKey', (newValue) ->
#   # `observe` calls immediately and every time the value is changed
#   console.log 'My configuration changed:', newValue
# ```
#
# If you want a notification only when the value changes, use {::onDidChange}.
#
# ```coffee
# atom.config.onDidChange 'my-package.myKey', ({newValue, oldValue}) ->
#   console.log 'My configuration changed:', newValue, oldValue
# ```
#
# ### Value Coercion
#
# Config settings each have a type specified by way of a
# [schema](json-schema.org). For example we might an integer setting that only
# allows integers greater than `0`:
#
# ```coffee
# # When no value has been set, `::get` returns the setting's default value
# atom.config.get('my-package.anInt') # -> 12
#
# # The string will be coerced to the integer 123
# atom.config.set('my-package.anInt', '123')
# atom.config.get('my-package.anInt') # -> 123
#
# # The string will be coerced to an integer, but it must be greater than 0, so is set to 1
# atom.config.set('my-package.anInt', '-20')
# atom.config.get('my-package.anInt') # -> 1
# ```
#
# ## Defining settings for your package
#
# Define a schema under a `config` key in your package main.
#
# ```coffee
# module.exports =
#   # Your config schema
#   config:
#     someInt:
#       type: 'integer'
#       default: 23
#       minimum: 1
#
#   activate: (state) -> # ...
#   # ...
# ```
#
# See [Creating a Package](https://atom.io/docs/latest/creating-a-package) for
# more info.
#
# ## Config Schemas
#
# We use [json schema](json-schema.org) which allows you to define your value's
# default, the type it should be, etc. A simple example:
#
# ```coffee
# # We want to provide an `enableThing`, and a `thingVolume`
# config:
#   enableThing:
#     type: 'boolean'
#     default: false
#   thingVolume:
#     type: 'integer'
#     default: 5
#     minimum: 1
#     maximum: 11
# ```
#
# The type keyword allows for type coercion and validation. If a `thingVolume` is
# set to a string `'10'`, it will be coerced into an integer.
#
# ```coffee
# atom.config.set('my-package.thingVolume', '10')
# atom.config.get('my-package.thingVolume') # -> 10
#
# # It respects the min / max
# atom.config.set('my-package.thingVolume', '400')
# atom.config.get('my-package.thingVolume') # -> 11
#
# # If it cannot be coerced, the value will not be set
# atom.config.set('my-package.thingVolume', 'cats')
# atom.config.get('my-package.thingVolume') # -> 11
# ```
#
# ### Supported Types
#
# The `type` keyword can be a string with any one of the following. You can also
# chain them by specifying multiple in an an array. For example
#
# ```coffee
# config:
#   someSetting:
#     type: ['boolean', 'integer']
#     default: 5
#
# # Then
# atom.config.set('my-package.someSetting', 'true')
# atom.config.get('my-package.someSetting') # -> true
#
# atom.config.set('my-package.someSetting', '12')
# atom.config.get('my-package.someSetting') # -> 12
# ```
#
# #### string
#
# Values must be a string.
#
# ```coffee
# config:
#   someSetting:
#     type: 'string'
#     default: 'hello'
# ```
#
# #### integer
#
# Values will be coerced into integer. Supports the (optional) `minimum` and
# `maximum` keys.
#
#   ```coffee
#   config:
#     someSetting:
#       type: 'integer'
#       default: 5
#       minimum: 1
#       maximum: 11
#   ```
#
# #### number
#
# Values will be coerced into a number, including real numbers. Supports the
# (optional) `minimum` and `maximum` keys.
#
# ```coffee
# config:
#   someSetting:
#     type: 'number'
#     default: 5.3
#     minimum: 1.5
#     maximum: 11.5
# ```
#
# #### boolean
#
# Values will be coerced into a Boolean. `'true'` and `'false'` will be coerced into
# a boolean. Numbers, arrays, objects, and anything else will not be coerced.
#
# ```coffee
# config:
#   someSetting:
#     type: 'boolean'
#     default: false
# ```
#
# #### array
#
# Value must be an Array. The types of the values can be specified by a
# subschema in the `items` key.
#
# ```coffee
# config:
#   someSetting:
#     type: 'array'
#     default: [1, 2, 3]
#     items:
#       type: 'integer'
#       minimum: 1.5
#       maximum: 11.5
# ```
#
# #### object
#
# Value must be an object. This allows you to nest config options. Sub options
# must be under a `properties key`
#
# ```coffee
# config:
#   someSetting:
#     type: 'object'
#     properties:
#       myChildIntOption:
#         type: 'integer'
#         minimum: 1.5
#         maximum: 11.5
# ```
#
# ### Other Supported Keys
#
# #### enum
#
# All types support an `enum` key. The enum key lets you specify all values
# that the config setting can possibly be. `enum` _must_ be an array of values
# of your specified type.
#
# ```coffee
# config:
#   someSetting:
#     type: 'integer'
#     default: 4
#     enum: [2, 4, 6, 8]
# ```
#
# ```coffee
# atom.config.set('my-package.someSetting', '2')
# atom.config.get('my-package.someSetting') # -> 2
#
# # will not set values outside of the enum values
# atom.config.set('my-package.someSetting', '3')
# atom.config.get('my-package.someSetting') # -> 2
#
# # If it cannot be coerced, the value will not be set
# atom.config.set('my-package.someSetting', '4')
# atom.config.get('my-package.someSetting') # -> 4
# ```
#
# #### title and description
#
# The settings view will use the `title` and `description` keys to display your
# config setting in a readable way. By default the settings view humanizes your
# config key, so `someSetting` becomes `Some Setting`. In some cases, this is
# confusing for users, and a more descriptive title is useful.
#
# Descriptions will be displayed below the title in the settings view.
#
# ```coffee
# config:
#   someSetting:
#     title: 'Setting Magnitude'
#     description: 'This will affect the blah and the other blah'
#     type: 'integer'
#     default: 4
# ```
#
# __Note__: You should strive to be so clear in your naming of the setting that
# you do not need to specify a title or description!
#
# ## Best practices
#
# * Don't depend on (or write to) configuration keys outside of your keypath.
#
module.exports =
class Config
  EmitterMixin.includeInto(this)
  @schemaEnforcers = {}

  @addSchemaEnforcer: (typeName, enforcerFunction) ->
    @schemaEnforcers[typeName] ?= []
    @schemaEnforcers[typeName].push(enforcerFunction)

  @addSchemaEnforcers: (filters) ->
    for typeName, functions of filters
      for name, enforcerFunction of functions
        @addSchemaEnforcer(typeName, enforcerFunction)

  @executeSchemaEnforcers: (keyPath, value, schema) ->
    error = null
    types = schema.type
    types = [types] unless Array.isArray(types)
    for type in types
      try
        enforcerFunctions = @schemaEnforcers[type].concat(@schemaEnforcers['*'])
        for enforcer in enforcerFunctions
          # At some point in one's life, one must call upon an enforcer.
          value = enforcer.call(this, keyPath, value, schema)
        error = null
        break
      catch e
        error = e

    throw error if error?
    value

  # Created during initialization, available as `atom.config`
  constructor: ({@configDirPath, @resourcePath}={}) ->
    @emitter = new Emitter
    @schema =
      type: 'object'
      properties: {}
    @defaultSettings = {}
    @settings = {}
    @configFileHasErrors = false
    @configFilePath = fs.resolve(@configDirPath, 'config', ['json', 'cson'])
    @configFilePath ?= path.join(@configDirPath, 'config.cson')

  ###
  Section: Config Subscription
  ###

  # Essential: Add a listener for changes to a given key path. This is different
  # than {::onDidChange} in that it will immediately call your callback with the
  # current value of the config entry.
  #
  # * `keyPath` {String} name of the key to observe
  # * `callback` {Function} to call when the value of the key changes.
  #   * `value` the new value of the key
  #
  # Returns a {Disposable} with the following keys on which you can call
  # `.dispose()` to unsubscribe.
  observe: (keyPath, options={}, callback) ->
    if _.isFunction(options)
      callback = options
      options = {}
    else
      message = ""
      message = "`callNow` was set to false. Use ::onDidChange instead. Note that ::onDidChange calls back with different arguments." if options.callNow == false
      deprecate "Config::observe no longer supports options. #{message}"

    callback(_.clone(@get(keyPath))) unless options.callNow == false
    @emitter.on 'did-change', (event) ->
      callback(event.newValue) if keyPath? and keyPath.indexOf(event?.keyPath) is 0

  # Essential: Add a listener for changes to a given key path. If `keyPath` is
  # not specified, your callback will be called on changes to any key.
  #
  # * `keyPath` (optional) {String} name of the key to observe
  # * `callback` {Function} to call when the value of the key changes.
  #   * `event` {Object}
  #     * `newValue` the new value of the key
  #     * `oldValue` the prior value of the key.
  #     * `keyPath` the keyPath of the changed key
  #
  # Returns a {Disposable} with the following keys on which you can call
  # `.dispose()` to unsubscribe.
  onDidChange: (keyPath, callback) ->
    if arguments.length is 1
      callback = keyPath
      keyPath = undefined

    @emitter.on 'did-change', (event) ->
      callback(event) if not keyPath? or (keyPath? and keyPath.indexOf(event?.keyPath) is 0)

  ###
  Section: Managing Settings
  ###

  # Essential: Retrieves the setting for the given key.
  #
  # * `keyPath` The {String} name of the key to retrieve.
  #
  # Returns the value from Atom's default settings, the user's configuration
  # file in the type specified by the configuration schema.
  get: (keyPath) ->
    value = _.valueForKeyPath(@settings, keyPath)
    defaultValue = _.valueForKeyPath(@defaultSettings, keyPath)

    if value?
      value = _.deepClone(value)
      valueIsObject = _.isObject(value) and not _.isArray(value)
      defaultValueIsObject = _.isObject(defaultValue) and not _.isArray(defaultValue)
      if valueIsObject and defaultValueIsObject
        _.defaults(value, defaultValue)
    else
      value = _.deepClone(defaultValue)

    value

  # Essential: Sets the value for a configuration setting.
  #
  # This value is stored in Atom's internal configuration file.
  #
  # * `keyPath` The {String} name of the key.
  # * `value` The value of the setting. Passing `undefined` will revert the
  #   setting to the default value.
  #
  # Returns a {Boolean}
  # * `true` if the value was set.
  # * `false` if the value was not able to be coerced to the type specified in the setting's schema.
  set: (keyPath, value) ->
    unless value == undefined
      try
        value = @makeValueConformToSchema(keyPath, value)
      catch e
        return false

    @setRawValue(keyPath, value)
    @save() unless @configFileHasErrors
    true

  # Extended: Restore the key path to its default value.
  #
  # * `keyPath` The {String} name of the key.
  #
  # Returns the new value.
  restoreDefault: (keyPath) ->
    @set(keyPath, _.valueForKeyPath(@defaultSettings, keyPath))
    @get(keyPath)

  # Extended: Get the default value of the key path. _Please note_ that in most
  # cases calling this is not necessary! {::get} returns the default value when
  # a custom value is not specified.
  #
  # * `keyPath` The {String} name of the key.
  #
  # Returns the default value.
  getDefault: (keyPath) ->
    defaultValue = _.valueForKeyPath(@defaultSettings, keyPath)
    _.deepClone(defaultValue)

  # Extended: Is the key path value its default value?
  #
  # * `keyPath` The {String} name of the key.
  #
  # Returns a {Boolean}, `true` if the current value is the default, `false`
  # otherwise.
  isDefault: (keyPath) ->
    not _.valueForKeyPath(@settings, keyPath)?

  # Extended: Retrieve the schema for a specific key path. The shema will tell
  # you what type the keyPath expects, and other metadata about the config
  # option.
  #
  # * `keyPath` The {String} name of the key.
  #
  # Returns an {Object} eg. `{type: 'integer', default: 23, minimum: 1}`.
  # Returns `null` when the keyPath has no schema specified.
  getSchema: (keyPath) ->
    keys = keyPath.split('.')
    schema = @schema
    for key in keys
      break unless schema?
      schema = schema.properties[key]
    schema

  # Extended: Returns a new {Object} containing all of settings and defaults.
  getSettings: ->
    _.deepExtend(@settings, @defaultSettings)

  # Extended: Get the {String} path to the config file being used.
  getUserConfigPath: ->
    @configFilePath

  ###
  Section: Deprecated
  ###

  getInt: (keyPath) ->
    deprecate '''Config::getInt is no longer necessary. Use ::get instead.
    Make sure the config option you are accessing has specified an `integer`
    schema. See the schema section of
    https://atom.io/docs/api/latest/Config for more info.'''
    parseInt(@get(keyPath))

  getPositiveInt: (keyPath, defaultValue=0) ->
    deprecate '''Config::getPositiveInt is no longer necessary. Use ::get instead.
    Make sure the config option you are accessing has specified an `integer`
    schema with `minimum: 1`. See the schema section of
    https://atom.io/docs/api/latest/Config for more info.'''
    Math.max(@getInt(keyPath), 0) or defaultValue

  toggle: (keyPath) ->
    deprecate 'Config::toggle is no longer supported. Please remove from your code.'
    @set(keyPath, !@get(keyPath))

  unobserve: (keyPath) ->
    deprecate 'Config::unobserve no longer does anything. Call `.dispose()` on the object returned by Config::observe instead.'

  ###
  Section: Private
  ###

  pushAtKeyPath: (keyPath, value) ->
    arrayValue = @get(keyPath) ? []
    result = arrayValue.push(value)
    @set(keyPath, arrayValue)
    result

  unshiftAtKeyPath: (keyPath, value) ->
    arrayValue = @get(keyPath) ? []
    result = arrayValue.unshift(value)
    @set(keyPath, arrayValue)
    result

  removeAtKeyPath: (keyPath, value) ->
    arrayValue = @get(keyPath) ? []
    result = _.remove(arrayValue, value)
    @set(keyPath, arrayValue)
    result

  initializeConfigDirectory: (done) ->
    return if fs.existsSync(@configDirPath)

    fs.makeTreeSync(@configDirPath)

    queue = async.queue ({sourcePath, destinationPath}, callback) ->
      fs.copy(sourcePath, destinationPath, callback)
    queue.drain = done

    templateConfigDirPath = fs.resolve(@resourcePath, 'dot-atom')
    onConfigDirFile = (sourcePath) =>
      relativePath = sourcePath.substring(templateConfigDirPath.length + 1)
      destinationPath = path.join(@configDirPath, relativePath)
      queue.push({sourcePath, destinationPath})
    fs.traverseTree(templateConfigDirPath, onConfigDirFile, (path) -> true)

  load: ->
    @initializeConfigDirectory()
    @loadUserConfig()
    @observeUserConfig()

  loadUserConfig: ->
    unless fs.existsSync(@configFilePath)
      fs.makeTreeSync(path.dirname(@configFilePath))
      CSON.writeFileSync(@configFilePath, {})

    try
      userConfig = CSON.readFileSync(@configFilePath)
      @settings = {} # Reset to the defaults
      if isPlainObject(userConfig)
        @setRecursive(null, userConfig)
      else
        @emitter.emit 'did-change'
      @configFileHasErrors = false
    catch error
      @configFileHasErrors = true
      console.error "Failed to load user config '#{@configFilePath}'", error.message
      console.error error.stack

  observeUserConfig: ->
    try
      @watchSubscription ?= pathWatcher.watch @configFilePath, (eventType) =>
        @loadUserConfig() if eventType is 'change' and @watchSubscription?
    catch error
      console.error "Failed to watch user config '#{@configFilePath}'", error.message
      console.error error.stack

  unobserveUserConfig: ->
    @watchSubscription?.close()
    @watchSubscription = null

  save: ->
    CSON.writeFileSync(@configFilePath, @settings)

  setRawValue: (keyPath, value) ->
    defaultValue = _.valueForKeyPath(@defaultSettings, keyPath)
    value = undefined if _.isEqual(defaultValue, value)

    oldValue = _.clone(@get(keyPath))
    _.setValueForKeyPath(@settings, keyPath, value)
    newValue = @get(keyPath)
    @emitter.emit 'did-change', {oldValue, newValue, keyPath} if newValue isnt oldValue

  setRawDefault: (keyPath, value) ->
    oldValue = _.clone(@get(keyPath))
    _.setValueForKeyPath(@defaultSettings, keyPath, value)
    newValue = @get(keyPath)
    @emitter.emit 'did-change', {oldValue, newValue, keyPath} if newValue isnt oldValue

  setRecursive: (keyPath, value) ->
    if value? and isPlainObject(value)
      keys = if keyPath? then keyPath.split('.') else []
      for key, childValue of value
        continue unless value.hasOwnProperty(key)
        @setRecursive(keys.concat([key]).join('.'), childValue)
    else
      try
        value = @makeValueConformToSchema(keyPath, value)
        @setRawValue(keyPath, value)
      catch e
        console.warn("'#{keyPath}' could not be set. Attempted value: #{JSON.stringify(value)}; Schema: #{JSON.stringify(@getSchema(keyPath))}")

    return

  setDefaults: (keyPath, defaults) ->
    if defaults? and isPlainObject(defaults)
      keys = if keyPath? then keyPath.split('.') else []
      for key, childValue of defaults
        continue unless defaults.hasOwnProperty(key)
        @setDefaults(keys.concat([key]).join('.'), childValue)
    else
      try
        defaults = @makeValueConformToSchema(keyPath, defaults)
        @setRawDefault(keyPath, defaults)
      catch e
        console.warn("'#{keyPath}' could not set the default. Attempted default: #{JSON.stringify(defaults)}; Schema: #{JSON.stringify(@getSchema(keyPath))}")

  setSchema: (keyPath, schema) ->
    unless isPlainObject(schema)
      throw new Error("Error loading schema for #{keyPath}: schemas can only be objects!")

    unless typeof schema.type?
      throw new Error("Error loading schema for #{keyPath}: schema objects must have a type attribute")

    rootSchema = @schema
    if keyPath
      for key in keyPath.split('.')
        rootSchema.type = 'object'
        rootSchema.properties ?= {}
        properties = rootSchema.properties
        properties[key] ?= {}
        rootSchema = properties[key]

    _.extend rootSchema, schema
    @setDefaults(keyPath, @extractDefaultsFromSchema(schema))

  extractDefaultsFromSchema: (schema) ->
    if schema.default?
      schema.default
    else if schema.type is 'object' and schema.properties? and isPlainObject(schema.properties)
      defaults = {}
      properties = schema.properties or {}
      defaults[key] = @extractDefaultsFromSchema(value) for key, value of properties
      defaults

  makeValueConformToSchema: (keyPath, value) ->
    value = @constructor.executeSchemaEnforcers(keyPath, value, schema) if schema = @getSchema(keyPath)
    value

# Base schema enforcers. These will coerce raw input into the specified type,
# and will throw an error when the value cannot be coerced. Throwing the error
# will indicate that the value should not be set.
#
# Enforcers are run from most specific to least. For a schema with type
# `integer`, all the enforcers for the `integer` type will be run first, in
# order of specification. Then the `*` enforcers will be run, in order of
# specification.
Config.addSchemaEnforcers
  'integer':
    coerce: (keyPath, value, schema) ->
      value = parseInt(value)
      throw new Error("Validation failed at #{keyPath}, #{JSON.stringify(value)} cannot be coerced into an int") if isNaN(value) or not isFinite(value)
      value

  'number':
    coerce: (keyPath, value, schema) ->
      value = parseFloat(value)
      throw new Error("Validation failed at #{keyPath}, #{JSON.stringify(value)} cannot be coerced into a number") if isNaN(value) or not isFinite(value)
      value

  'boolean':
    coerce: (keyPath, value, schema) ->
      switch typeof value
        when 'string'
          if value.toLowerCase() is 'true'
            true
          else if value.toLowerCase() is 'false'
            false
          else
            throw new Error("Validation failed at #{keyPath}, #{JSON.stringify(value)} must be a boolean or the string 'true' or 'false'")
        when 'boolean'
          value
        else
          throw new Error("Validation failed at #{keyPath}, #{JSON.stringify(value)} must be a boolean or the string 'true' or 'false'")

  'string':
    validate: (keyPath, value, schema) ->
      unless typeof value is 'string'
        throw new Error("Validation failed at #{keyPath}, #{JSON.stringify(value)} must be a string")
      value

  'null':
    # null sort of isnt supported. It will just unset in this case
    coerce: (keyPath, value, schema) ->
      throw new Error("Validation failed at #{keyPath}, #{JSON.stringify(value)} must be null") unless value == null
      value

  'object':
    coerce: (keyPath, value, schema) ->
      throw new Error("Validation failed at #{keyPath}, #{JSON.stringify(value)} must be an object") unless isPlainObject(value)
      return value unless schema.properties?

      newValue = {}
      for prop, childSchema of schema.properties
        continue unless value.hasOwnProperty(prop)
        try
          newValue[prop] = @executeSchemaEnforcers("#{keyPath}.#{prop}", value[prop], childSchema)
        catch error
          console.warn "Error setting item in object: #{error.message}"
      newValue

  'array':
    coerce: (keyPath, value, schema) ->
      throw new Error("Validation failed at #{keyPath}, #{JSON.stringify(value)} must be an array") unless Array.isArray(value)
      itemSchema = schema.items
      if itemSchema?
        newValue = []
        for item in value
          try
            newValue.push @executeSchemaEnforcers(keyPath, item, itemSchema)
          catch error
            console.warn "Error setting item in array: #{error.message}"
        newValue
      else
        value

  '*':
    coerceMinimumAndMaximum: (keyPath, value, schema) ->
      return value unless typeof value is 'number'
      if schema.minimum? and typeof schema.minimum is 'number'
        value = Math.max(value, schema.minimum)
      if schema.maximum? and typeof schema.maximum is 'number'
        value = Math.min(value, schema.maximum)
      value

    validateEnum: (keyPath, value, schema) ->
      possibleValues = schema.enum
      return value unless possibleValues? and Array.isArray(possibleValues) and possibleValues.length

      for possibleValue in possibleValues
        # Using `isEqual` for possibility of placing enums on array and object schemas
        return value if _.isEqual(possibleValue, value)

      throw new Error("Validation failed at #{keyPath}, #{JSON.stringify(value)} is not one of #{JSON.stringify(possibleValues)}")

isPlainObject = (value) ->
  _.isObject(value) and not _.isArray(value) and not _.isFunction(value) and not _.isString(value)
