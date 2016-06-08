/*
<Application>: tmx2c <Version>: 1.0.0 <Author>: Joshua Adam Reisenauer <Email>: kd7tck@gmail,com.
<LICENCE>: C0 2016 Joshua Adam Reisenauer.
This program is convered by a dual liscence.
First liscence is public domain, the second is GPL 3 found at <http://www.gnu.org/licenses/gpl-3.0.en.html>.

Compilation Instructions:

	go get "github.com/davecgh/go-spew/spew"

	go get "github.com/kd7tck/jar/tmx2c"

CMD INPUT:

	Pass in tmx files as arguments.
	Make sure to use absolute paths eg: "c:\path\to\file\filename.tmx"

CMD OUTPUT:

	Output is a file in CWD named out.h
*/
package main

import (
	"encoding/xml"
	"io/ioutil"
	"os"

	//download this lib before compiling
	"github.com/davecgh/go-spew/spew"

	"bytes"
	"errors"
	"path/filepath"
	"strings"
)

// Holds one static image, typically for backgrounds
type Tmximagelayer struct {
	Name    string `xml:"name,attr"`
	Offsetx string `xml:"offsetx,attr"`
	Offsety string `xml:"offsety,attr"`
	X       string `xml:"x,attr"`
	Y       string `xml:"y,attr"`
	Width   string `xml:"width,attr"`
	Height  string `xml:"height,attr"`
	Opacity string `xml:"opacity,attr"`
	Visible string `xml:"visible,attr"`

	Image      Tmximage      `xml:"image"`
	Properties Tmxproperties `xml:"properties"`
}

type Tmxelipse struct {
	NODATAINELIPSE string
}

type Tmxpolygon struct {
	Points string `xml:"points,attr"`
}

type Tmxpolyline struct {
	Points string `xml:"points,attr"`
}

type Tmxobject struct {
	Id       string `xml:"id,attr"`
	Name     string `xml:"name,attr"`
	Type     string `xml:"type,attr"`
	X        string `xml:"x,attr"`
	Y        string `xml:"y,attr"`
	Width    string `xml:"width,attr"`
	Height   string `xml:"height,attr"`
	Rotation string `xml:"rotation,attr"`
	Gid      string `xml:"gid,attr"`
	Visible  string `xml:"visible,attr"`

	Elipse     []Tmxelipse   `xml:"ellipse"`
	Polygon    []Tmxpolygon  `xml:"polygon"`
	PolyLine   []Tmxpolyline `xml:"polyline"`
	Properties Tmxproperties `xml:"properties"`
}

type Tmxobjectgroup struct {
	Name      string `xml:"name,attr"`
	Color     string `xml:"color,attr"`
	X         string `xml:"x,attr"`
	Y         string `xml:"y,attr"`
	Width     string `xml:"width,attr"`
	Height    string `xml:"height,attr"`
	Opacity   string `xml:"opacity,attr"`
	Visible   string `xml:"visible,attr"`
	Offsetx   string `xml:"offsetx,attr"`
	Offsety   string `xml:"offsety,attr"`
	Draworder string `xml:"draworder,attr"`

	Objects    []Tmxobject   `xml:"object"`
	Properties Tmxproperties `xml:"properties"`
}

type Tmxframe struct {
	TileID   string `xml:"tileid,attr"`
	Duration string `xml:"duration,attr"`
}

type Tmxanimation struct {
	Frames []Tmxframe `xml:"frame"`
}

type Tmxproperty struct {
	Name  string `xml:"name,attr"`
	Type  string `xml:"type,attr"`
	Value string `xml:"value,attr"`
}

type Tmxproperties struct {
	Properties []Tmxproperty `xml:"property"`
}

type Tmxdata struct {
	Encoding string `xml:"encoding,attr"`
	MapData  string `xml:",innerxml"`

	Tiles []Tmxtile `xml:"tile"`
}

type Tmxlayer struct {
	Name    string `xml:"name,attr"`
	Width   string `xml:"width,attr"`
	Height  string `xml:"height,attr"`
	Visible string `xml:"visible,attr"`
	Opacity string `xml:"opacity,attr"`
	Offsetx string `xml:"offsetx,attr"`
	Offsety string `xml:"offsety,attr"`

	Properties Tmxproperties `xml:"properties"`
	Data       Tmxdata       `xml:"data"`
}

type Tmximage struct {
	Format string `xml:"format,attr"`
	Id     string `xml:"id,attr"`
	Source string `xml:"source,attr"`
	Trans  string `xml:"trans,attr"`
	Width  string `xml:"width,attr"`
	Height string `xml:"height,attr"`

	Data Tmxdata `xml:"data"`
}

type Tmxtileoffset struct {
	X string `xml:"x,attr"`
	Y string `xml:"y,attr"`
}

type Tmxterrain struct {
	Name string `xml:"name,attr"`
	Tile string `xml:"tile,attr"`

	Properties Tmxproperties `xml:"properties"`
}

type Tmxterraintypes struct {
	Terrains []Tmxterrain `xml:"terrain"`
}

type Tmxtile struct {
	Id          string `xml:"id,attr"`
	Terrain     string `xml:"terrain,attr"`
	Probability string `xml:"probability,attr"`

	Properties  Tmxproperties    `xml:"properties"`
	Image       Tmximage         `xml:"image"`
	Animation   Tmxanimation     `xml:"animation"`
	ObjectGroup []Tmxobjectgroup `xml:"objectgroup"`
}

type Tmxtileset struct {
	Firstgid   string `xml:"firstgid,attr"`
	Source     string `xml:"source,attr"`
	Name       string `xml:"name,attr"`
	Tilewidth  string `xml:"tilewidth,attr"`
	Tileheight string `xml:"tileheight,attr"`
	Spacing    string `xml:"spacing,attr"`
	Margin     string `xml:"margin,attr"`
	Tilecount  string `xml:"tilecount,attr"`
	Columns    string `xml:"columns,attr"`

	Properties   Tmxproperties   `xml:"properties"`
	Images       []Tmximage      `xml:"image"`
	TileOffset   Tmxtileoffset   `xml:"tileoffset"`
	TerrainTypes Tmxterraintypes `xml:"terraintypes"`
	Tiles        []Tmxtile       `xml:"tile"`
}

type Tmxmap struct {
	Version         string `xml:"version,attr"`
	Orientation     string `xml:"orientation,attr"`
	RenderOrder     string `xml:"renderorder,attr"`
	Width           string `xml:"width,attr"`
	Height          string `xml:"height,attr"`
	TileWidth       string `xml:"tilewidth,attr"`
	TileHeight      string `xml:"tileheight,attr"`
	StaggerAxis     string `xml:"staggeraxis,attr"`
	StaggerIndex    string `xml:"staggerindex,attr"`
	NextObjectID    string `xml:"nextobjectid,attr"`
	BackGroundColor string `xml:"backgroundcolor,attr"`

	Properties  Tmxproperties    `xml:"properties"`
	TileSets    []Tmxtileset     `xml:"tileset"`
	Layers      []Tmxlayer       `xml:"layer"`
	ObjectGroup []Tmxobjectgroup `xml:"objectgroup"`
	ImageLayers []Tmximagelayer  `xml:"imagelayer"`
}

func OpenXML(arg string) (Tmxmap, error) {
	var tmap Tmxmap

	xmlFile, err := os.Open(arg)
	check(err)
	if err != nil {
		return tmap, err
	}
	defer xmlFile.Close()

	b, _ := ioutil.ReadAll(xmlFile)
	xml.Unmarshal(b, &tmap)

	return tmap, nil
}

func check(e error) {
	if e != nil {
		spew.Sdump(e)
		panic(e)
	}
}

func write2file(f *os.File, s []byte) {
	_, err := f.Write(s)
	check(err)
	f.Sync()
}

//ToDo, still incomplete!
func ConvertToC(tmap Tmxmap, filename string) []byte {
	var buffer bytes.Buffer
	buffer.Write([]byte("#define "));buffer.Write([]byte(filename));buffer.Write([]byte("_Version "));buffer.Write([]byte(tmap.Version))
	buffer.Write([]byte("\n#define "));buffer.Write([]byte(filename));buffer.Write([]byte("_Orientation "));buffer.Write([]byte(tmap.Orientation))
	return buffer.Bytes()
}

func main() {
	arguments := os.Args[1:]

	f, err := os.Create("out.h")
	check(err)
	defer f.Close()

	for _, arg := range arguments {

		if filepath.IsAbs(arg) == false { //only absolute paths are accepted for Spliting
			newpath, err := filepath.Abs(arg)
			if err != nil {
				err2 := errors.New("Input path is not absolute")
				spew.Sdump(err2)
				continue
			}
			arg = newpath
		}

		var buffer bytes.Buffer
		tmap, err2 := OpenXML(arg)
		if err2 == nil {
			_, filename := filepath.Split(arg) //get filename from arg
			filename = strings.Replace(filename, ".", "_", -1)
			buffer.Write([]byte("#ifdef "))
			buffer.Write([]byte(filename))
			buffer.Write([]byte("_MAP\n"))
			buffer.Write(ConvertToC(tmap, filename))
			buffer.Write([]byte("\n#endif"))
			write2file(f, buffer.Bytes())
		}
	}
}
