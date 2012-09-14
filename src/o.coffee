mongoose = require('mongoose')

path = require('path')
fs = require('fs')
mkdirp = require('mkdirp')
im = require('imagemagick')
async = require('async')

embedly = require('embedly')
require_either = embedly.utils.require_either
#util = require_either('util', 'utils')
util = require('util')

Schema = mongoose.Schema
ObjectId = Schema.ObjectId

# ---------------------------------------------------------------------
#   helper functions
# ---------------------------------------------------------------------

is_callable = (f) ->
  (typeof f is 'function')

# get value from dictionary, returning the specified default if key is not there
get = (o, key, dflt) ->
  if key of o
    return o[key]
  return dflt

# Extend a source object with the properties of another object (shallow copy).
extend = (dst, src) ->
  for key, val of src
    dst[key] = val
  dst

defaults = (dst, src) ->
  for key, val of src
    if not (key of dst)
      dst[key] = val
  dst

addSchemaField = (schema, pathname, fieldSpec) ->
  fieldSchema = {}
  fieldSchema[pathname] = fieldSpec
  schema.add fieldSchema

# ---------------------------------------------------------------------
#   M O N G O O S E   P L U G I N S
# ---------------------------------------------------------------------
# http://mongoosejs.com/docs/plugins.html

createdModifiedPlugin = (schema, options={}) ->
  defaults options,
    createdName: 'created'
    modifiedName: 'modified'
    index: false
  createdName = options.createdName
  modifiedName = options.modifiedName
  addSchemaField schema, createdName,
    type: Date
    default: () -> null
  addSchemaField schema, modifiedName,
    type: Date
    default: () -> null
  schema.pre "save", (next) ->
    @[modifiedName] = new Date()
    if @.get(createdName) in [undefined, null]
      @[createdName] = new Date()
    next()

  schema.path(createdName).index options.index  if options.index
  schema.path(modifiedName).index options.index  if options.index

filePlugin = (schema, options={}) ->
  pathname = options.name or 'file'
  onChangeCb = options.change_cb or null
  upload_to = options.upload_to or null     # if null, uploaded file is left in the temp upload dir
  relative_to = options.relative_to or null # if null, .rel field is equal to .path

  # fieldSchema = {}
  # fieldSchema[pathname] = {} # mixed: { type: Schema.Types.Mixed }
  # schema.add fieldSchema
  # fieldSchema = {}
  # fieldSchema["#{pathname}.name"] = String
  # schema.add fieldSchema
  # fieldSchema = {}
  # fieldSchema["#{pathname}.path"] = String
  # schema.add fieldSchema
  # fieldSchema = {}
  # fieldSchema["#{pathname}.type"] = {type: String}
  # schema.add fieldSchema
  # fieldSchema = {}
  # fieldSchema["#{pathname}.size"] = Number
  # schema.add fieldSchema
  # fieldSchema = {}
  # fieldSchema["#{pathname}.lastModified"] = Date
  # schema.add fieldSchema

  fieldSchema = {}
  fieldSchema[pathname] =
    name: String
    path: String
    rel: String
    type: String
    size: Number
    lastModified: Date
  schema.add fieldSchema
  fieldSchema = {}
  fieldSchema[pathname] = {} # mixed: { type: Schema.Types.Mixed }
  schema.add fieldSchema

  schema.virtual("#{pathname}.file").set (fileObj) ->
    u_path = fileObj.path
    if upload_to
      # move from temp. upload directory to final destination
      if is_callable(upload_to)
        dst = upload_to.call(@, fileObj)
      else
        dst = path.join(upload_to, fileObj.name)
      dst_dirname = path.dirname(dst)
      mkdirp dst_dirname, (err) =>
        throw err  if err
        fs.rename u_path, dst, (err) =>
          if (err)
            # delete the temporary file, so that the explicitly set temporary upload dir does not get filled with unwanted files
            fs.unlink u_path, (err) =>
              throw err  if err
            throw err
          console.log("moved from #{u_path} to #{dst}")
          rel = dst
          if relative_to
            if is_callable(relative_to)
              rel = relative_to.call(@, fileObj)
            else
              rel = path.relative(relative_to, dst)
          @set("#{pathname}.name", fileObj.name)
          @set("#{pathname}.path", dst)
          @set("#{pathname}.rel", rel)
          @set("#{pathname}.type", fileObj.type)
          @set("#{pathname}.size", fileObj.size)
          @set("#{pathname}.lastModified", fileObj.lastModifiedDate)
          @markModified(pathname)
    else
      dst = u_path
      rel = dst
      if relative_to
        if is_callable(relative_to)
          rel = relative_to.call(@, fileObj)
        else
          rel = path.relative(relative_to, dst)
      @set("#{pathname}.name", fileObj.name)
      @set("#{pathname}.path", dst)
      @set("#{pathname}.rel", rel)
      @set("#{pathname}.type", fileObj.type)
      @set("#{pathname}.size", fileObj.size)
      @set("#{pathname}.lastModified", fileObj.lastModifiedDate)
      @markModified(pathname)
  schema.pre 'set', (next, path, val, typel) ->
    if path is "#{pathname}.path"
      if onChangeCb
        oldValue = @get("#{pathname}.path")
        console.log("old: #{oldValue} new: #{val}")
        onChangeCb.call(@, pathname, val, oldValue)
    next()

make_upload_to_model = (basedir, subdir) ->
  b_dir = basedir
  s_dir = subdir
  upload_to_model = (fileObj) ->
    dstdir = b_dir
    if s_dir
      dstdir = path.join(dstdir, s_dir)
    id = @get('id')
    if id
      dstdir = path.join(dstdir, "#{id}")
    path.join(dstdir, fileObj.name)
  upload_to_model

imageThumbnailPlugin = (schema, options={}) ->
  onChangeCbOrig = options.change_cb or null

  change_cb = (pathname, path, oldPath) ->
    if onChangeCbOrig
        onChangeCbOrig.apply(@, arguments)
    if oldPath
      fs.unlink oldPath, (err) ->
        if (err)
          console.log("An error happened removing file #{oldPath}: #{err}")
    instance = @
    image_path = path
    console.log("Resizing #{image_path}")
    im.resize {
      srcData: fs.readFileSync image_path, 'binary'
      width: size
      format: format
      filter: 'Lanczos'     # 'Lagrange'
    }, (err, stdout, stderr) =>
      throw err  if (err)
      @set("#{pathname}.#{thumb}", "data:image/#{format};base64," + new Buffer(stdout, 'binary').toString('base64'))
      @markModified(pathname)
      @save()
  options.change_cb = change_cb
  filePlugin(schema, options)

  pathname = options.name or 'file'
  thumb = options.thumb or 'thumb'
  format = options.format or 'jpg'
  size = options.size or 96
  fieldSchema = {}
  fieldSchema["#{pathname}.#{thumb}"] = String
  schema.add fieldSchema

# -- Embedly support --------------------------------------------------

embedly_cache = {}

embedlyPlugin = (schema, options={}) ->
  embedly_key = options.embedly_key
  embedly_api = options.embedly_api or new embedly.Api({user_agent: 'Mozilla/5.0 (compatible; myapp/1.0; u@my.com)', key: embedly_key})

  pathname = options.name or 'url'
  oembed_pathname = options.oembed_name or 'oembed'
  oembed_opts = options.oembed_options or {}

  fieldSchema = {}
  fieldSchema[oembed_pathname] = {} # mixed: { type: Schema.Types.Mixed }
  schema.add fieldSchema

  add_oembed_info = (instance, url, oembed_objs) ->
    console.log("Adding OEmbed info to instance for url:#{url}")
    oembed_info = instance.get(oembed_pathname) or {}
    oembed_info[pathname] = oembed_objs[0]
    instance.set(oembed_pathname,  oembed_info)
    instance.markModified(oembed_pathname)
    instance.save()
    instance

  schema.pre 'set', (next, path, val, typel) ->
    if path != pathname
      return next()
    oldValue = @get(pathname)
    if val is oldValue
      return next()
    instance = @
    url = val
    if url of embedly_cache
      add_oembed_info(instance, url, embedly_cache[url])
    else
      opts = {urls: [url]}
      oembed_opts = oembed_opts or {}
      extend(opts, oembed_opts)
      #console.log(opts)
      embedly_api.oembed(opts).on('complete', (objs) ->
        #console.log(util.inspect(objs[0]))
        embedly_cache[url] = objs
        add_oembed_info(instance, url, objs)
      ).on('error', (e) ->
        console.error('embedly request failed')
        console.error(e)
      ).start()
    next()

# -- exports ----------------------------------------------------------

module.exports =
  createdModifiedPlugin: createdModifiedPlugin
  filePlugin: filePlugin
  imageThumbnailPlugin: imageThumbnailPlugin
  embedlyPlugin: embedlyPlugin
