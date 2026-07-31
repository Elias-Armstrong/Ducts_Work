# Ducts Work

This is a SketchUp Extension written in Ruby, designed to streamline the process of laying out HVAC and water pipework in a residential/small commercial model. It contains a variety of modular pieces,         including pipes, tees, wyes, elbows, increasers, vents, and crosses. Ducts Work also contains tools for resizing ducts, fitting ducts to exact measurements, rotating duct pieces, and adding repeat vent        elements across a whole section.
Unlike more basic geometry tools and piece builders, Ducts Work uses a graph of duct pieces and explicit inter-piece connections. It also utilizes automatic multi-strategy routing, topology-aware resizing     tools, persistent reconstruction between saves and exits, and transaction safe editing.


State of the Program: 

    Ducts Work is fully functioning, and is currently at a stage with real utility. All of the core features work under normal conditions. However, in the future, more vent models and options for pipe finish      would bring this program to the next level. In addition, weird user inputs occasionally cause bugs, but we're at the point where "rational" pipe placement does not cause issues. 



Primary Features:

Ducts: 
    Drawing Round and Rectangular Ducts
    Automatic insertion of elbows
    Straight-Only Routing when needed
    Axis Locks and Length inputting for precise measurements 
    Real time route previews. 

Connections and Ports: 
    Snap to existing connections across sessions 
    Detection of nearby fitting geometry and pipe orientation
    Automatic pipe alignment through elbow additions when necessary 
    
Fittings:
    Inline Tees
    End Tees
    Crosses
    Wyes
    Elbows
    Rectangular-to-circular converter 
    Increasers
    Reducers
    Side Registers
    End Covers
    
    These can all be added to a model through the right click menu with the extension running.     



Automatic Size Transitions: 
    
    When ducts of two different sizes connect, an increaser is automatically added to the passive side of the connection at the standard execution slope for increasers and reducers (2.1 * largest initial          dimension, 3 times size change, or 10 inches, whichever is largest). Connection components always keep their same size, and increasers/reducers will be added directly to their ports to accomodate, moving      the active port in the process.  
    
    For example:

        8-inch active duct
                |
                v
        New 8-inch route (unchanged) -> 8-to-12-inch increaser -> 12-inch existing duct


Fitting Rotation Tool: 
     Connection pieces can be rotated manually through a built in tool that handles duct pieces better than the SketchUp native version. 
    
        Ctrl-Click will rotation 45 degrees at the time, measured from the starting orientation (decided by initial click direction). 
        Ctrl-Drag will rotate along with the cursor, snapping to the closest 15 degrees upon release. 
        Rotation cannot be used on multiple components at once. This was briefly implemented, but proved to be a general nuisance, so it was removed. Instead, click a component on the end. 
        The entire drag is also recorded as one SketchUp undo action now, so can be easily undone with ctrl-Z.


Resize Command:
     From the toolbar, you can resize an entire run, including end components and pieces. Select a section, click the "Resize Pipe" option on the toolbar, and then click your desired new size. This will also 
     add increasers and reducers to any old connections to the run as needed, but may require manual re-evaluation of some of the cross connections if they were designed to have a smaller off-branch and are 
     now overlapping with existing geometry. 

     
Installation Instructions: 

    1. Download the Repository 
    2. Copy the extension's files in the SketchUp Plugins directory, which (on Windows) is located at: 
        C:\Users\<username>\AppData\Roaming\SketchUp\SketchUp 2026\SketchUp\Plugins
    3. Restart SketchUp if necessary
    4. The menu should appear on screen, with the first 3 loadup options. It will either be in the top toolbar already, or in the middle of your screen. If it doesn't appear, go to the Extensions tab at the          top of your screen. If it doesn't load there, contact me at elias_armstrong@mines.edu and I'd be happy to help.  

    The application structure should be:
        Plugins/
        ├── ducts_work.rb
        └── ducts_work/
            ├── main.rb
            ├── geometry/
            ├── model/
            ├── services/
            ├── tool/
            └── ui/


Other Basic Usage Instructions: 
        Drawing a Duct: 
            1. Click the "Draw Orthoganol Duct" option of the extension menu, then select desired parameters for your pipes
            2. Click any point on screen, then
                a) click another point to create a straight run
             OR b) use the arrow keys on your keyboard to lock your run to a specific axis
             OR c) type numbers on your number pad to input a desired length in feet along the current direction of the mouse from start. You can then use the ' key to switch from feet to inches. 
            3. Click a different third point to create another run starting at your previous endpoint. Elbows will be added automatically

         Adding Other Components: 
             1. Click the "Draw Orthoganol Duct" Option of the extension menu, then select desired parameters for your pipes 
             2. Right click to open the dropdown menu
             3. Select "New Components", and select your desired piece
             4. Left Click the end of a different component, and, if needed, select desired parameters 

        
         Special Instructions for Vents: 
             1. In the right click menu, click the "Vent Repeat" option 
             2. Set desired repeating options, including direction, and distance. Next time you place a vent, it will follow these instructions 
        
         
         Resizing: 
             1. Left click and drag over a section of pipes and components 
             2. Click the "Resize Selected Duct Pieces" in the top menu
             3. Select desired new size

         Clearing Duct Data: 
             This tool is used to delete the graph data and metadata associated with your pipes in the current model. In large models, this can help with performance, and can also protect the existing geometry             if you are using other extensions or modules that are untested. 
            
             1. Click the "Clear Duct Data" option on the menu at the top of your screen
             2. Accept the risks of this action in the text box  
                
        

         Information about the Preview:
             The placement preview hologram will appear whenever you are one click away from placing a new run. Green means you are connecting to an existing run, orange means you are running along an axis,
             and red means you are placing a non-axis aligned component that does not connect to an old run. 



Structure and Important Archictectural Information: 

         As shown above, this is a basic diagram of the structure of the program: 

            ducts_work/
            ├── main.rb         #Dependency loading, namespace setup, startup management and handling of the extension
            ├── geometry/       #Geometry Builders, geometric utilities, and most of the mathematical functions for deciding where pieces ought to be placed that are shared across the whole program
            ├── model/          #Duct pieces, ports, connections, networks, dimensions, and definitions for most of the graph rules and components
            ├── services/       #Routing service, fitting insertions, resizing, snapping, rotating, and most of the individual functions of the tools
            ├── tool/           #Where most of the full tools actually reside, and user input handling
            └── ui/             #Toolbar management, command registration, and a lot of the random SketchUp side of things

            
          Architecture: 
            Key Terms Include: 
            
              DuctPiece: Pipes, Connectors, or related components
              Port: A connection point with direction, position, and related dimensions
              Network: The grid of pieces with explicit port-to-port connections
              ModelOperation: Transaction handling, network reconstruction, rollback, and related tasks
              DuctDimensions: Normalized round of rectangular size information and characteristics
            
            Responsibilities are deliberately seperated: 
              Geometry builders create the duct geometry and necessary fittings
              Routing services determine valid routes and orientations 
              Transition services are used to create adaption pieces, seamlessly blend transitions, and determine proper placement for increasers and reducers
              Port-Cap services manager fitting closure faces during the construction of new components
              Network services preserve connection topology for future reconnstruction. 



Technology: 
        Ruby 
        SketchUp Ruby API
        SketchUp geometric entities
        Custom routing
        Custom graph network modeling


Authorship:
        Developed by Elias Armstrong for JLA Design, LLC. Contact the developer at elias_armstrong@mines.edu. 
