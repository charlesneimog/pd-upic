<p align="center">
  <h2 align="center">pd-upic</h2>
  <h4 align="center">SVG as music scores</h4>
</p>

--- 
`pd-upic` is a Pure Data (Pd) external object inspired by the works of Iannis Xenakis. This object is designed to facilitate the conversion of SVG (Scalable Vector Graphics) data into coordinate information within the Pure Data environment.


> [!WARNING]  
> `pd-upic` is distributed as part of the `pd-xlab` library. 


## Download and Install

1. Create a new Pure Data patch.
2. Go to Help → Find Externals → and Search for `xlab`.
3. Create a new object `declare -lib xlab`.
4. Create one of the objects.

   
## List of Objects

Check [https://charlesneimog.github.io/?blog=pd-upic](https://charlesneimog.github.io/?blog=pd-upic) to learn how to build the SVG file.

### Playback

- **`l.readsvg`**: 
  - Method: `read` the SVG file, requires the SVG file.
  - Method: `play` the SVG file;
  - Method: `stop` the player;
    
### Message Retrieval

- **`l.getmsgs`**: 
  - Method: Get all messages set in the properties text input inside Inkscape.
  
### Attributes

- **`l.attrfilter`**: Filter object by attribute.
    - Available attributes are: `fill`, `stroke`, `type`, `duration`, `onset`. 
  
- **`l.attrget`**: Method to get the values of some attribute for some SVG form.

### Sub-Events

Sub-Events are SVGs draw inside SVGs draws. 

- **`l.getchilds`**: Returns a list with all the child of the event.  
- **`l.playchilds`**: Put the children on time, playing following the onset of the father.

### Paths
- **`l.getpath`**: Get the complete path of paths.
- **`l.playpath`**: Play the complete path of paths.

