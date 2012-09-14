mongoose = require('mongoose')
filePluginLib = require('mongoose-file')

path = require('path')
fs = require('fs')
util = require('util')
mkdirp = require('mkdirp')
temp = require('temp')
im = require('imagemagick')

Schema = mongoose.Schema
ObjectId = Schema.ObjectId

# ---------------------------------------------------------------------
#   helper functions
# ---------------------------------------------------------------------

# Extend a source object with the properties of another object (shallow copy).
extend = (dst, src) ->
  for key, val of src
    dst[key] = val
  dst

# Add missing properties from a `src` object.
defaults = (dst, src) ->
  for key, val of src
    if not (key of dst)
      dst[key] = val
  dst

# Add a new field by name to a mongoose schema
addSchemaField = (schema, pathname, fieldSpec) ->
  fieldSchema = {}
  fieldSchema[pathname] = fieldSpec
  schema.add fieldSchema

addSchemaSubField = (schema, masterPathname, subName, fieldSpec) ->
  addSchemaField schema, "#{masterPathname}.#{subName}", fieldSpec

is_callable = (f) ->
  (typeof f is 'function')

# ---------------------------------------------------------------------
#   M O N G O O S E   P L U G I N S
# ---------------------------------------------------------------------
# http://mongoosejs.com/docs/plugins.html

filePlugin = filePluginLib.filePlugin
make_upload_to_model = filePluginLib.make_upload_to_model

thumbnailPlugin = (schema, options={}) ->
  onChangeCbOrig = options.change_cb or null

  change_cb = (pathname, newPath, oldPath) ->
    if onChangeCbOrig
        onChangeCbOrig.apply(@, arguments)
    if oldPath
      fs.unlink oldPath, (err) ->
        if (err)
          console.log("An error happened removing file #{oldPath}: #{err}")
    instance = @
    image_path = newPath
    thumb_basename = path.basename(image_path)
    if '.' in thumb_basename
      thumb_basename = path.basename(thumb_basename, path.extname(thumb_basename))
    thumb_basename = thumb_prefix + thumb_basename + ".#{format}"
    tmp_thumb_path = temp.path({suffix: ".#{format}"})
    dst_thumb_path = path.join(path.dirname(image_path), thumb_basename)

    rel_thumb_path = dst_thumb_path
    if relative_to
      if is_callable(relative_to)
        rel_thumb_path = relative_to.call @,
          size: null
          path: dst_thumb_path
          name: thumb_basename
          type: 'image/#{format}'
          hash: false
          lastModifiedDate: new Date()
      else
        rel_thumb_path = path.relative(relative_to, dst_thumb_path)

    console.log("Resizing #{image_path}")
    im_resize_opts = 
      width: size
      format: format
      filter: 'Lanczos'     # 'Lagrange'
    if modeInline
      im_resize_opts.srcData = fs.readFileSync image_path, 'binary'
    else
      im_resize_opts.srcPath = image_path
      im_resize_opts.dstPath = tmp_thumb_path
    im.resize im_resize_opts, (err, stdout, stderr) =>
      # console.log("RESIZE OP TERMINATED. ERROR:", err)
      throw err  if (err)
      if modeInline
        @set("#{pathname}.#{thumb}", "data:image/#{format};base64," + new Buffer(stdout, 'binary').toString('base64'))
        @markModified(pathname)
        if do_save
          @save()
      else
        fs.rename tmp_thumb_path, dst_thumb_path, (err) =>
          if (err)
            # delete the temporary file, so that the explicitly set temporary upload dir does not get filled with unwanted files
            fs.unlink tmp_thumb_path, (err) =>
              throw err  if err
            throw err
          # console.log("Moved thumb to #{dst_thumb_path}")
          @set("#{pathname}.#{thumb}.name", thumb_basename)
          @set("#{pathname}.#{thumb}.path", dst_thumb_path)
          @set("#{pathname}.#{thumb}.rel", rel_thumb_path)
          @markModified(pathname)
          if do_save
            @save()
  options.change_cb = change_cb
  filePlugin(schema, options)

  pathname = options.name or 'file'
  thumb = options.thumb or 'thumb'
  format = options.format or 'jpg'
  size = options.size or 96
  relative_to = options.thumb_relative_to or options.relative_to or null # if null, .rel field is equal to .path
  thumb_prefix = options.thumb_prefix or "t_"
  do_save = true
  if options and options.save?
    do_save = options.save
  modeInline = false
  if options and options.inline?
    modeInline = options.inline

  if modeInline
    addSchemaSubField schema, pathname, thumb, { type: String, default: () -> null }
  else
    addSchemaSubField schema, pathname, thumb, {} # mixed: { type: Schema.Types.Mixed }
    addSchemaSubField schema, pathname, "#{thumb}.name", { type: String, default: () -> null }
    addSchemaSubField schema, pathname, "#{thumb}.path", { type: String, default: () -> null }
    addSchemaSubField schema, pathname, "#{thumb}.rel", { type: String, default: () -> null }

# -- exports ----------------------------------------------------------

module.exports =
  thumbnailPlugin: thumbnailPlugin
  filePlugin: filePlugin
  make_upload_to_model: make_upload_to_model
