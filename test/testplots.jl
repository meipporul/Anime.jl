#=@testset "PA and Elevation" begin
    y = YAML.load_file("data/testconfig.yaml", dicttype=Dict{String,Any}) # sample dict to test loadms()

    obs = loadms(y["msname"], y["stations"], Int(y["corruptseed"]), Int(y["troposphere"]["tropseed"]), y["troposphere"]["wetonly"], y["correff"], 
    y["troposphere"]["attenuate"], y["troposphere"]["skynoise"], y["troposphere"]["meandelays"], y["troposphere"]["turbulence"], 
    y["instrumentalpol"]["visibilityframe"], y["instrumentalpol"]["mode"], y["pointing"]["interval"], y["pointing"]["mode"], y["stationgains"]["mode"], 
    y["bandpass"]["bandpassfile"], delim=",", ignorerepeated=false)

    @inferred parallacticangle(obs.times, obs.phasedir, obs.stationinfo, obs.pos)
    @inferred elevationangle(obs.times, obs.phasedir, obs.stationinfo, obs.pos)
end=#

@testset "Plots" begin
    y = YAML.load_file("data/config1.yaml", dicttype=Dict{String,Any}) # sample dict to test loadms()
    h5file = "data/insmodel1.h5"

    obs = loadms(y["msname"], y["stations"], Int(y["corruptseed"]), Int(y["troposphere"]["tropseed"]), y["troposphere"]["wetonly"], y["correff"], 
    y["troposphere"]["attenuate"], y["troposphere"]["skynoise"], y["troposphere"]["meandelays"], y["troposphere"]["turbulence"], 
    y["instrumentalpol"]["visibilityframe"], y["instrumentalpol"]["mode"], y["pointing"]["interval"], y["pointing"]["mode"], y["stationgains"]["mode"], 
    y["bandpass"]["bandpassfile"], delim=",", ignorerepeated=false)

    @inferred plotvis(obs.uvw, obs.chanfreqvec, obs.flag, obs.data, obs.numchan, obs.times, saveprefix="test_")
    rm("test_visampvspbs.png")
    rm("test_visphasevspbs.png")
    rm("test_visampvstime.png")
    rm("test_visphasevstime.png")


    @inferred plotstationgains(h5file, obs.scanno, obs.times, obs.stationinfo.station)
    rm("stationgainsvstime.png")

    @inferred plotbandpass(h5file, obs.stationinfo.station, obs.chanfreqvec)
    rm("bandpassgains.png")

    @inferred plotpointingerrors(h5file, obs.scanno, obs.stationinfo.station)
    rm("pointingoffsets.png")
    rm("pointingamplitudeerrors.png")
end