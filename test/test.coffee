chai = require 'chai'
assert = chai.assert
expect = chai.expect
should = chai.should()
mongoose = require 'mongoose'

fs = require 'fs'
path = require 'path'
util = require 'util'

index = require '../src/index'

PLUGIN_TIMEOUT = 3000

rmDir = (dirPath) ->
  try
    files = fs.readdirSync(dirPath)
  catch e
    return
  if files.length > 0
    i = 0

    while i < files.length
      continue if files[i] in ['.', '..']
      filePath = dirPath + "/" + files[i]
      if fs.statSync(filePath).isFile()
        fs.unlinkSync filePath
      else
        rmDir filePath
      i++
  fs.rmdirSync dirPath

filecopy = (src, dst, cb) ->
  copy = (err) ->
    is_ = undefined
    os = undefined
    return cb(new Error("File " + dst + " exists."))  unless err
    fs.stat src, (err) ->
      return cb(err)  if err
      is_ = fs.createReadStream(src)
      os = fs.createWriteStream(dst)
      util.pump is_, os, cb

  fs.stat dst, copy

String::beginsWith = (str) -> if @match(new RegExp "^#{str}") then true else false
String::endsWith = (str) -> if @match(new RegExp "#{str}$") then true else false

db = mongoose.createConnection('localhost', 'mongoose_thumbnail_tests')
db.on('error', console.error.bind(console, 'connection error:'))

uploads_base = __dirname + "/uploads"
uploads = uploads_base + "/u"

origImagePath = path.join(__dirname, path.join('assets', 'lena.png'))
tmpFilePath = '/tmp/mongoose-thumbnail-test.png'
uploadedDate = new Date()
uploadedFile =
  size: 476254
  path: tmpFilePath
  name: 'lena.png'
  type: 'image/png',
  hash: false,
  lastModifiedDate: uploadedDate

Schema = mongoose.Schema
ObjectId = Schema.ObjectId

schemaDef =
  name: String
  title: String

_schemas_and_models = {}
_next_schema_num = 0

getNewSchemaAndModel = (plug_cb) ->
  num = _next_schema_num
  _next_schema_num += 1
  schema = new Schema(schemaDef)
  if plug_cb
    plug_cb.call(@, schema, num)
  model = db.model("SimpleModel#{num}", schema)
  data =
    schema: schema
    model: model
  _schemas_and_models[num] = data
  return data

getSchemaAndModel = (num) ->
  if (num >= 0) and (num < _next_schema_num)
    return _schemas_and_models[num]

describe 'WHEN working with the plugin', ->
  before (done) ->
    done()

  after (done) ->
    for num in [0..._next_schema_num]
      {model, schema} = getSchemaAndModel num
    model.remove {}, (err) ->
      return done(err)  if err
    rmDir(uploads_base)
    done()

  describe 'library', ->
    it 'should exist', (done) ->
      should.exist index
      done()

  describe 'adding the plugin for non-inline thumbnail', ->
    it 'should add correct properties', (done) ->

      {model, schema} = getNewSchemaAndModel (schema) ->
        schema.plugin index.thumbnailPlugin,
          name: "photo"
          inline: false
          upload_to: index.make_upload_to_model(uploads, 'photos')
          relative_to: uploads_base
  
      instance = new model({name: 'testName', title: 'testTitle'})
      should.exist instance
      should.equal instance.isModified(), true
      instance.should.have.property 'name', 'testName'
      instance.should.have.property 'title', 'testTitle'
      instance.should.have.property 'photo'
      should.exist instance.photo
      instance.photo.should.have.property 'thumb'
      instance.photo.should.have.property 'name'
      instance.photo.should.have.property 'path'
      instance.photo.should.have.property 'rel'
      instance.photo.should.have.property 'type'
      instance.photo.should.have.property 'size'
      instance.photo.should.have.property 'lastModified'

      should.exist instance.photo.thumb
      should.not.exist instance.photo.thumb.name
      should.not.exist instance.photo.thumb.path
      should.not.exist instance.photo.thumb.rel
      done()

  describe 'adding the plugin for inline thumbnail', ->
    it 'should add correct properties', (done) ->

      {model, schema} = getNewSchemaAndModel (schema) ->
        schema.plugin index.thumbnailPlugin,
          name: "photo"
          inline: true
          upload_to: index.make_upload_to_model(uploads, 'photos')
          relative_to: uploads_base
  
      instance = new model({name: 'testName', title: 'testTitle'})
      should.exist instance
      should.equal instance.isModified(), true
      instance.should.have.property 'name', 'testName'
      instance.should.have.property 'title', 'testTitle'
      instance.should.have.property 'photo'
      should.exist instance.photo
      instance.photo.should.have.property 'thumb'
      instance.photo.should.have.property 'name'
      instance.photo.should.have.property 'path'
      instance.photo.should.have.property 'rel'
      instance.photo.should.have.property 'type'
      instance.photo.should.have.property 'size'
      instance.photo.should.have.property 'lastModified'

      should.not.exist instance.photo.thumb
      done()

  describe 'assigning to the instance field for non-inline thumbnail', ->
    it 'should properly populate subfields', (done) ->

      {model, schema} = getNewSchemaAndModel (schema) ->
        schema.plugin index.thumbnailPlugin,
          name: "photo"
          inline: false
          upload_to: index.make_upload_to_model(uploads, 'photos')
          relative_to: uploads_base
  
      instance = new model({name: 'testName', title: 'testTitle'})
      should.exist instance
      should.exist instance.photo
      should.exist instance.photo.thumb
      should.equal instance.isModified(), true

      filecopy origImagePath, tmpFilePath, (err) ->
        return done(err)  if (err)

        instance.set('photo.file', uploadedFile)
        # give the plugin some time to notice the assignment and execute its
        # asynchronous code
        setTimeout ->
          # assigning to image field causes the instance to be saved
          should.equal instance.isModified(), false
          should.exist instance.photo.thumb
          should.exist instance.photo.name
          should.exist instance.photo.path
          should.exist instance.photo.rel
          should.exist instance.photo.type
          should.exist instance.photo.size
          should.exist instance.photo.lastModified

          instance.photo.thumb.should.have.property 'name'
          instance.photo.thumb.should.have.property 'path'
          instance.photo.thumb.should.have.property 'rel'

          should.equal instance.photo.thumb.name, 't_lena.jpg'
          should.equal instance.photo.thumb.rel, path.join(path.join("u", path.join("photos", instance.id)), 't_lena.jpg')
          should.equal instance.photo.name, uploadedFile.name
          should.not.equal instance.photo.path, uploadedFile.path
          should.equal instance.photo.type, uploadedFile.type
          should.equal instance.photo.size, uploadedFile.size
          should.equal instance.photo.lastModified, uploadedFile.lastModifiedDate

          done()
        , PLUGIN_TIMEOUT

  describe 'assigning to the instance field for inline thumbnail', ->
    it 'should properly populate subfields', (done) ->

      {model, schema} = getNewSchemaAndModel (schema) ->
        schema.plugin index.thumbnailPlugin,
          name: "photo"
          inline: true
          format: 'jpg'
          upload_to: index.make_upload_to_model(uploads, 'photos')
          relative_to: uploads_base
  
      instance = new model({name: 'testName', title: 'testTitle'})
      should.exist instance
      should.exist instance.photo
      should.equal instance.isModified(), true

      filecopy origImagePath, tmpFilePath, (err) ->
        return done(err)  if (err)

        instance.set('photo.file', uploadedFile)
        # give the plugin some time to notice the assignment and execute its
        # asynchronous code
        setTimeout ->
          # assigning to image field causes the instance to be saved
          should.equal instance.isModified(), false
          should.exist instance.photo.thumb
          should.exist instance.photo.name
          should.exist instance.photo.path
          should.exist instance.photo.rel
          should.exist instance.photo.type
          should.exist instance.photo.size
          should.exist instance.photo.lastModified

          instance.photo.thumb.should.be.a 'string'
          should.equal instance.photo.thumb.beginsWith("data:image/jpg;base64,"), true

          should.equal instance.photo.name, uploadedFile.name
          should.not.equal instance.photo.path, uploadedFile.path
          should.equal instance.photo.type, uploadedFile.type
          should.equal instance.photo.size, uploadedFile.size
          should.equal instance.photo.lastModified, uploadedFile.lastModifiedDate

          done()
        , PLUGIN_TIMEOUT

  describe 'assigning to the instance field', ->
    it 'should NOT mark as modified when save is set to true', (done) ->

      {model, schema} = getNewSchemaAndModel (schema) ->
        schema.plugin index.thumbnailPlugin,
          name: "photo"
          inline: false
          upload_to: index.make_upload_to_model(uploads, 'photos')
          relative_to: uploads_base
          save: true
  
      instance = new model({name: 'testName', title: 'testTitle'})
      should.exist instance
      should.equal instance.isModified(), true

      instance.save (err) ->
        return done(err)  if err

        should.equal instance.isModified(), false

        filecopy origImagePath, tmpFilePath, (err) ->
          return done(err)  if (err)

          instance.set('photo.file', uploadedFile)
          # give the plugin some time to notice the assignment and execute its
          # asynchronous code
          setTimeout ->
            # assigning to image field causes the instance to be saved
            should.equal instance.isModified(), false

            instance.save (err) ->
              return done(err)  if err

              should.equal instance.isModified(), false

              done()
          , PLUGIN_TIMEOUT

  describe 'assigning to the instance field', ->
    it 'should mark as modified when save is set to false', (done) ->

      {model, schema} = getNewSchemaAndModel (schema) ->
        schema.plugin index.thumbnailPlugin,
          name: "photo"
          inline: false
          upload_to: index.make_upload_to_model(uploads, 'photos')
          relative_to: uploads_base
          save: false
  
      instance = new model({name: 'testName', title: 'testTitle'})
      should.exist instance
      should.equal instance.isModified(), true

      instance.save (err) ->
        return done(err)  if err

        should.equal instance.isModified(), false

        filecopy origImagePath, tmpFilePath, (err) ->
          return done(err)  if (err)

          instance.set('photo.file', uploadedFile)
          # give the plugin some time to notice the assignment and execute its
          # asynchronous code
          setTimeout ->
            should.equal instance.isModified(), true

            instance.save (err) ->
              return done(err)  if err

              should.equal instance.isModified(), false

              done()
          , PLUGIN_TIMEOUT
