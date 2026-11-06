<h1>Auto-Camera</h1>
A World of Warcraft addon that augments the camera's functionality and control.

<h2>Zoom Tab</h2>
- While active, this feature smoothly transitions camera distance based on various configurable contexts (e.g. running, riding, fighting an enemy, fighting a bunch of enemies, etc.)<br/>
- Stand-By mode allows the player to quickly disable automatic zooming if necessary.<br/>
    - By default the camera zooms to View 5 (Views are configurable camera distances available in the base game). This behavior can be changed in the "/ac settings" panel.<br/>
    - You can toggle Stand-By with a macro ("/ac toggle") or a key binding which can be set in the "/ac settings" panel.<br/>
    - Auto-Camera enters Stand-By automatically for the duration of some events (e.g. boss encounters and pet battles).<br/>

<h2>Action Tab</h2>
- Provides a settings interface for the base game's experimental Action Cam feature.<br/>

<h2>Slash Commands</h2>
/ac &nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbspdisplay console command options<br/>
/ac toggle&nbsp&nbsp&nbsp&nbsp&nbsptoggles stand-by mode on/off<br/>
/ac standby&nbsp&nbsp&nbspenters stand-by mode<br/>
/ac resume&nbsp&nbsp&nbsp&nbspexits stand-by mode<br/>
/ac settings&nbsp&nbsp&nbspopens Auto-Camera settings<br/>

<h2>Local Flavor Testing</h2>
The base <code>Auto-Camera.toc</code> is generated locally and ignored by Git. To select a flavor for live testing, run:

<pre>bash ./scripts/use-flavor.sh [flavor]</pre>

The flavor defaults to <code>retail</code>. Supported flavors are <code>retail</code>, <code>anniversary</code>, <code>classic-era</code>, <code>mop-classic</code>, and <code>forever</code>.
