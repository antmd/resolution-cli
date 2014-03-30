resolution-cli
==============

A command line tool for switching display modes on OS X

    resolution-cli: Change the screen resolution on OS X

     Usage: resolution-cli <command> [<argument> [<argument>]]

        Commands:
        
        list
            list the available resolutions

        set [<display-index>] <resolution>
            set the resolution. If no display-index is specified, set the main display resolution
        
        
        <resolution> can be specified in several ways, and an underscore can be used
        anywhere a number might be used meaning 'match anything' in a search from highest-
        resolution to lowest resolution.
        
        Examples for <resolution>:
            1920x1080@32h = display mode size 1920x1080, 32 bit colour, HiDPI
            2560      = first mode with 2560 width
            1920x1080 = first mode with size 1920x1080
            _x900     = first mode with height 900
            _x_@16    = first mode with 16-bit colour
            h         = first HiDPI mode
            _         = Highest resolution mode -- often the default


The details of the private CGS* display functions to detect and change resolutions were originally worked out by Robbert Klarenbeek, and used in his excellent [ResolutionMenu](https://github.com/robbertkl/ResolutionMenu).
