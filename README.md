## pd-upic

`pd-upic` is a Pure Data (Pd) external object inspired by the works of Iannis Xenakis. This object is designed to facilitate the conversion of SVG (Scalable Vector Graphics) data into coordinate information within the Pure Data environment.

## List of Objects

### Playback

- **`u.readsvg`**: 
  - Method: `read` the SVG file, requires the SVG file.
  - Method: `play` the SVG file;
  - Method: `stop` the player;
    
### Message Retrieval

- **`u.getmsgs`**: 
  - Method: Get all messages set in the properties text input inside Inkscape.
  
### Attributes

- **`u.attrfilter`**: Filter object by attribute.
    - Available attributes are: `fill`, `stroke`, `type`, `duration`, `onset`. 
  
- **`u.attrget`**: Method to get the values of some attribute for some SVG form.

### Sub-Events

Sub-Events are SVGs draw inside SVGs draws. 

- **`u.getchilds`**: Returns a list with all the child of the event.  
- **`u.playchilds`**: Put the children on time, playing following the onset of the father.

### Paths
- **`u.getpath`**: Get the complete path of paths.
- **`u.playpath`**: Play the complete path of paths.


## Install

1. Create a new Pure Data patch.
2. Go to Help → Find Externals → and Search for `pd-upic`.
3. Create a new object `declare -lib pdlua`.
4. Create one of the objects.


