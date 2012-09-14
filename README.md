## About mongoose-thumbnail

[mongoose][] plugin that adds a thumbnail field to a mongoose schema.
This is especially suited to handle image file uploads with [nodejs][]/[expressjs][].

## Install

npm install mongoose-thumbnail

## Usage

The plugin adds a thumbnail field to the mongoose schema.
As it uses [mongoose-file][] internally, the added field has all the `mongoose-file` field sub-properties.
Please refer to [mongoose-file][] documentation to understand basic usage.

In addition to the sub-fields carried by [mongoose-file][], this plugin creates an additional sub-field, named by default `thumb`.
Depending on the `inline` plugin option, the thumbnail field may contain additional sub-fields containing the thumbnail file properties, or could be a string containing the [Data URI](http://en.wikipedia.org/wiki/Data_URI_scheme) encoded thumbnail.

In addition those pertaining to [mongoose-file][], the following options are available:

* `thumb` - the name of the thumbnail sub-field (defaults to `thumb`)
* `format` - the image format for the thumbnail (defaults to `jpg`)
* `size` - the side size of the thumbnail (by default `96`)
* `thumb_prefix` - the prefix for the thumbnail files (defaults to `t_`)
* `inline` - if `true` the thumbnail is not saved to a file but directly in the mongoose document, in the thumbnail sub-field, encoded as a string using the [Data URI scheme](http://en.wikipedia.org/wiki/Data_URI_scheme) (defaults to `false`)
* `save` - if `true` the model instance is saved after every assignment to the image field (change to the `file` sub-property) (defaults to `true`)

Please note that this library re-exports also `filePlugin` and `make_upload_to_model`.

### JavaScript

```javascript
var mongoose = require('mongoose');
var thumbnailPluginLib = require('mongoose-thumbnail');
var thumbnailPlugin = thumbnailPluginLib.thumbnailPlugin;
var make_upload_to_model = thumbnailPluginLib.make_upload_to_model;

...

var uploads_base = path.join(__dirname, "uploads");
var uploads = path.join(uploads_base, "u");
...

var SampleSchema = new mongoose.Schema({
  ...
});
SampleSchema.plugin(thumbnailPlugin, {
	name: "photo",
	format: "png",
	size: 80,
	inline: false,
	save: true,
	upload_to: make_upload_to_model(uploads, 'photos'),
	relative_to: uploads_base
});
var SampleModel = db.model("SampleModel", SampleSchema);
```

### [CoffeeScript][]

```coffeescript
mongoose = require 'mongoose'
filePluginLib = require 'mongoose-thumbnail'
filePlugin = filePluginLib.filePlugin
make_upload_to_model = filePluginLib.make_upload_to_model

...
uploads_base = path.join(__dirname, "uploads")
uploads = path.join(uploads_base, "u")
...

SampleSchema = new mongoose.Schema
  ...
SampleSchema.plugin thumbnailPlugin
	name: "photo"
	format: "png"
	size: 80
	inline: false
	save: true
	upload_to: make_upload_to_model(uploads, 'photos')
	relative_to: uploads_base
SampleModel = db.model("SampleModel", SampleSchema)
```

### Using with express

```coffeescript

PictureSchema = new mongoose.Schema
  title: String
PictureSchema.plugin thumbnailPlugin
  name: "photo"
  inline: false
Picture = db.model("Picture", PictureSchema)

...

app.post "/upload", (req, res, next) ->
  picture = new Picture({title: req.body.title})
  picture.set('image.file', req.files.image)
  picture.save (err) ->
    return next(err)  if (err)
  res.redirect '/'
```

Now in a [Jade][] template, you could have something like:

```
<img src="/{{ picture.image.thumb.rel }}" />
```

Otherwise, using thumbnail inlining:

```coffeescript

PictureSchema = new mongoose.Schema
  title: String
PictureSchema.plugin thumbnailPlugin
  name: "photo"
  inline: true
Picture = db.model("Picture", PictureSchema)
```

the template would use:

```
<img src="{{ picture.image.thumb }}" />
```

## Bugs and pull requests

Please use the github [repository][] to notify bugs and make pull requests.

## License

This software is © 2012 Marco Pantaleoni, released under the MIT licence. Use it, fork it.

See the LICENSE file for details.

[mongoose]: http://mongoosejs.com
[CoffeeScript]: http://jashkenas.github.com/coffee-script/
[nodejs]: http://nodejs.org/
[expressjs]: http://expressjs.com
[Mocha]: http://visionmedia.github.com/mocha/
[Jade]: http://jade-lang.com
[mongoose-file]: https://npmjs.org/package/mongoose-file
[repository]: http://github.com/panta/mongoose-thumbnail
