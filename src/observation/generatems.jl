export generatems

# import python libraries
simulator = pyimport("casatools" => "simulator")
sm = simulator()

tb = table()
me = measures()

importuvfits = pyimport("casatasks" => "importuvfits")

function makecasaanttable(stations::String, delim::String, ignorerepeated::Bool, casaanttemplate::String)
    """
    Generate a CASA antenna table from CSV station info file in the current working directory.
    """
    # read in the stations CSV file
    df = CSV.read(stations, DataFrame; delim=delim, ignorerepeated=ignorerepeated)
    
    stationtable = "ANTENNA_$(split(basename(stations), '.')[1])"

    # read template table and copy
    tb.open(casaanttemplate)
    tb.copy(stationtable, deep=true, valuecopy=true)
    tb.close()
    tb.clearlocks()

    # populate new table with values from the DataFrame
    tb.open(stationtable, nomodify=false)
    for ii in 1:length(df.station)-1
        tb.copyrows(stationtable, nrow=1)
    end
    tb.putcol("STATION", PyList(string.(df.station)))
    tb.putcol("NAME", PyList(string.(df.station))) # same as station names
    tb.putcol("MOUNT", PyList(string.(df.mount)))
    tb.putcol("DISH_DIAMETER", PyList(df.dishdiameter_m))
    #for jj in 1:length(df.station)
    #	tb.putcell("POSITION", jj-1, PyList(parse.(Float64, split.(df.xyzpos_m,',')[jj])))
    #end
    index = 0
    for (x,y,z) in zip(df.x_m,df.y_m,df.z_m)
        tb.putcell("POSITION", index, PyList([x,y,z]))
        index += 1
    end
    tb.close()
    tb.clearlocks()

    return stationtable
end

function msfromvex()
end

function msfromuvfits(yamlconf::Dict, delim::String, ignorerepeated::Bool)
    """
    Create MS from uvfits file.
    """
    # convert uvfits to ms
    importuvfits(fitsfile=yamlconf["uvfits"]["fitsfile"], vis=yamlconf["msname"])

    # compare ANTENNA table in ms with stations file
    df = CSV.read(yamlconf["stations"], DataFrame; delim=delim, ignorerepeated=ignorerepeated)

    tb.open("$(yamlconf["msname"])::ANTENNA")
    msstations = string.(tb.getcol("STATION"))
    tb.close()

    if !(issetequal(msstations, df.station))
        error("Station info file $(yamlconf["stations"]) and MS ANTENNA table do not match 🤷")
    end
   
    # if specified, replace EXPOSURE column with user-supplied value
    if !(yamlconf["uvfits"]["exposure"] == 0.0)
	@info("Replacing (potentially inconsistent) EXPOSURE column in MS with user-supplied value: $(yamlconf["uvfits"]["exposure"]) s")
        tb.open(yamlconf["msname"], nomodify=false)
	exposurevec = yamlconf["uvfits"]["exposure"] .+ zeros(Float64, pyconvert(Int64, tb.nrows()))
        tb.putcol("EXPOSURE", PyList(exposurevec))
        tb.putcol("INTERVAL", PyList(exposurevec))
	tb.close()
    end

    #= create weight and sigma spectrum columns
    table = CCTable(yamlconf["msname"], CCTables.Update)
    x = size(table[:DATA])[1]
    y, z = size(table[:DATA][1])
    table[:WEIGHT_SPECTRUM] = ones(Float32, y, z, x)::Array{Float32, 3} # Float32 to conform to the MSv2 specification (which WSClean expects... sometimes!)
    table[:SIGMA_SPECTRUM] = ones(Float32, y, z, x)::Array{Float32, 3}
    table = nothing
    GC.gc()=#
end

#=function setupexistingms(yamlconf::Dict, delim::String, ignorerepeated::Bool)
    """
    Perform some sanity checks on an existing MS.
    """
    # symlink existing ms to output directory
    symlink = `ln -s $(yamlconf["existingms"]["msname"]) $(yamlconf["msname"])`
    run(symlink)

    # compare ANTENNA table in existing ms with stations file
    df = CSV.read(yamlconf["stations"], DataFrame; delim=delim, ignorerepeated=ignorerepeated)

    tb.open("$(yamlconf["msname"])::ANTENNA")
    msstations = string.(tb.getcol("STATION"))
    tb.close()

    if !(issetequal(msstations, df.station))
        error("Station info file $(yamlconf["stations"]) and MS ANTENNA table do not match 🤷")
    end

    # zero all values in DATA and MODEL_DATA
    #=tb.open(yamlconf["msname"], nomodify=false)
    nrows = pyconvert(Int64, tb.nrows())
    cell = pyconvert(Tuple, tb.getcell("DATA", rownr=0).shape)=#
    table = CCTable(yamlconf["msname"], CCTables.Update)
    data = table[:DATA][:]
    zmat = zeros(typeof(data[1][1,1]), size(data[1]))
    zdata = [data[ii] = zmat for ii in 1:length(data)]
    table[:DATA] = zdata

    # if MODEL_DATA does not exist, create it and fill it with zeros (using Casacore.jl implicit construction)
    table[:MODEL_DATA] = zdata

    # if specified, replace EXPOSURE column with user-supplied value
    if !(yamlconf["existingms"]["exposure"] == 0.0)
	@info("Replacing (potentially inconsistent) EXPOSURE column in MS with user-supplied value: $(yamlconf["existingms"]["exposure"]) s")
	table[:EXPOSURE] = yamlconf["existingms"]["exposure"] .+ zeros(Float64, length(data))
    end
    
    @info("Set up existing dataset at $(yamlconf["existingms"]["msname"]) as $(yamlconf["msname"])... 🙆")
end=#

function msfromconfig(yamlconf::Dict, delim::String, ignorerepeated::Bool, casaanttemplate::String)
    """
    Main function to generate MS.
    """
    # open new MS
    sm.open(yamlconf["msname"])

    # set autocorr
    Bool(yamlconf["autocorr"]) ? sm.setauto(autocorrwt=1.0) : sm.setauto(autocorrwt=0.0)
    
    # set antenna config -- optionally create a new CASA ANTENNA table if the station info is in a CSV file
    stationtable = ""
    if isfile(yamlconf["stations"])
	# check if template is specified
	casaanttemplate == nothing && error("$(yamlconf["stations"]) is a CSV file but template CASA ANTENNA table not specified 🤷")
	stationtable = makecasaanttable(yamlconf["stations"], delim, ignorerepeated, casaanttemplate)
	@info("Creating new ANTENNA table from CSV station info file...")
    elseif isdir(yamlconf["stations"])
	stationtable = yamlconf["stations"]
    else
        error("$(yamlconf["stations"]) does not exist 🤷")
    end

    # station locations are contained in a casa antenna table
    tb.open(stationtable)
    station_code = tb.getcol("STATION")
    dish_diameter = tb.getcol("DISH_DIAMETER")
    station_mount = tb.getcol("MOUNT")
    x, y, z = tb.getcol("POSITION")
    tb.close()
    tb.clearlocks()

    coords = "global" # CASA antenna tables use ITRF by default
    obspos = me.observatory(yamlconf["telescopename"])
    me.doframe(obspos)

    # NB: For any Python array with strings, convert elements to Julia strings and cast the entire Vector to PyList()
    sm.setconfig(telescopename=yamlconf["telescopename"], x=x, y=y, z=z,
		 dishdiameter=dish_diameter, mount=PyList(string.(station_mount)), antname=PyList(string.(station_code)),
		 padname=PyList(string.(station_code)), coordsystem=coords, referencelocation=obspos)

    # set feed
    sm.setfeed(mode=yamlconf["feed"])

    # set limits for data flagging
    sm.setlimits(shadowlimit=yamlconf["shadowlimit"], elevationlimit=yamlconf["elevationlimit"])

    # set spectral windows -- NB: we are not handling multiple spws as of now
    #=for (key, val) in yamlconf["manual"]["spwname"]
	startfreq = val["centrefreq"] - val["bandwidth"]-2.0
	chanwidth = val["bandwidth"]/val["channels"]
	sm.setspwindow(spwname=key, freq="$(startfreq)GHz",
		deltafreq="$(chanwidth)GHz", freqresolution="$(chanwidth)GHz",
		nchannels=val["channels"], stokes=yamlconf["manual"]["stokes"])
    end=#
    for ind in 1:length(yamlconf["spw"]["centrefreq"])
        chanwidth = yamlconf["spw"]["bandwidth"][ind]/yamlconf["spw"]["channels"][ind]
        startfreq = yamlconf["spw"]["centrefreq"][ind] - yamlconf["spw"]["bandwidth"][ind]/2. + chanwidth/2.
	sm.setspwindow(spwname="$(Int(yamlconf["spw"]["centrefreq"][ind]/1e9))GHz", freq="$(startfreq)Hz",
        	deltafreq="$(chanwidth)Hz", freqresolution="$(chanwidth)Hz",
		nchannels=yamlconf["spw"]["channels"][ind], stokes=yamlconf["stokes"])
    end

    # set obs fields
    for (key, val) in yamlconf["source"]
	sm.setfield(sourcename=key, sourcedirection=me.direction(rf=val["epoch"], v0=val["RA"], v1=val["Dec"]))
    end

    # set obs times
    obs_starttime = split(yamlconf["starttime"], ",")
    referencetime = me.epoch(obs_starttime...)
    me.doframe(referencetime)
    sm.settimes(integrationtime=yamlconf["exposure"], usehourangle=false, referencetime=referencetime)

    # observe
    Int64(yamlconf["scans"]) != length(yamlconf["scanlengths"]) && error("Number of scans and length(scanlengths_s) do not match 🤷")
    Int64(yamlconf["scans"]) != length(yamlconf["scanlags"])+1 && error("Number of scans and length(scanlaglist)+1 do not match 🤷")

    stoptime = 0
    for ii in 1:Int64(yamlconf["scans"])
	starttime = ii==1 ? 0 : stoptime+yamlconf["scanlags"][ii-1]
	stoptime = starttime + yamlconf["scanlengths"][ii] #+ yamlconf["exposure"] # one more exposure added here at the end of the scan

	# NB: We are not handling multiple spectral windows as of now
	#=for (key, val) in yamlconf["manual"]["spwname"]
	    sm.observe(sourcename=collect(keys(yamlconf["manual"]["source"]))[1], spwname=key, starttime="$(starttime)s", stoptime="$(stoptime)s")
	end=#
	for ind in 1:length(yamlconf["spw"]["centrefreq"])
            sm.observe(sourcename=collect(keys(yamlconf["source"]))[1], spwname="$(Int(yamlconf["spw"]["centrefreq"][ind]/1e9))GHz", starttime="$(starttime)s", stoptime="$(stoptime)s")
	end
    end

    # clean up
    sm.close()

    # create weight and sigma spectrum columns
    table = CCTable(yamlconf["msname"], CCTables.Update)
    x = size(table[:DATA])[1]
    y, z = size(table[:DATA][1])
    table[:WEIGHT_SPECTRUM] = ones(Float32, y, z, x)::Array{Float32, 3} # Float32 to conform to the MSv2 specification (which WSClean expects... sometimes!)
    table[:SIGMA_SPECTRUM] = ones(Float32, y, z, x)::Array{Float32, 3} 

    @info("Create $(yamlconf["msname"])... 🙆")
end

function generatems(yamlconf::Dict, delim::String, ignorerepeated::Bool, casaanttemplate::String)
    if yamlconf["mode"] == "manual"
	msfromconfig(yamlconf, delim, ignorerepeated, casaanttemplate)
    elseif yamlconf["mode"] == "uvfits"
	msfromuvfits(yamlconf, delim, ignorerepeated)
    else
	error("MS generation mode '$(yamlconf["mode"])' not recognised 🤷")
    end
end
