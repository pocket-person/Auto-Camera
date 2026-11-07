<h1>Auto-Camera</h1>
A World of Warcraft addon that augments the camera's functionality and control.

<h2>Auto Zoom Settings</h2>
- While active, this feature smoothly transitions camera distance based on various configurable contexts (e.g. running, riding, fighting an enemy, fighting a bunch of enemies, etc.)<br/>
- Pause allows the player to quickly disable automatic zooming if necessary.<br/>
    - By default the camera zooms to View 5 (Views are configurable camera distances available in the base game). This behavior can be changed in the "/ac settings" panel.<br/>
    - You can toggle Pause with a macro ("/ac toggle") or a key binding which can be set in the "/ac settings" panel.<br/>
    - Auto-Camera pauses automatically for the duration of some events (e.g. boss encounters and pet battles).<br/>

<h2>Action Camera Settings</h2>
- Provides a searchable settings subcategory for the base game's experimental Action Cam feature.<br/>

<h2>Slash Commands</h2>
/ac &nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbspdisplay console command options<br/>
/ac toggle&nbsp&nbsp&nbsp&nbsp&nbsptoggles pause on/off<br/>
/ac pause&nbsp&nbsp&nbsp&nbsp&nbsp&nbsppauses auto-zoom<br/>
/ac standby&nbsp&nbsp&nbspalias for /ac pause (also /ac stand-by)<br/>
/ac resume&nbsp&nbsp&nbsp&nbspresumes auto-zoom<br/>
/ac settings&nbsp&nbsp&nbspopens Auto-Camera settings<br/>

<h2>Config Migration Recovery</h2>
Migration is validated on a copy before the saved database is changed. If it fails, Auto-Camera stops, reports the error in chat, and offers the option to reset to defaults, or disable the addon.<br/>

<h2>Local Flavor Testing</h2>
The base <code>Auto-Camera.toc</code> is generated locally and ignored by Git. To select a flavor for live testing, run:

<pre>bash ./scripts/use-flavor.sh [flavor]</pre>

The flavor defaults to <code>retail</code>. Supported flavors are <code>retail</code>, <code>anniversary</code>, <code>classic-era</code>, <code>mop-classic</code>, and <code>forever</code>.
