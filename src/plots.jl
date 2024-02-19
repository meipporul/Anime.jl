export plotvis, plotstationgains

"""
    plotvis(uvw::Matrix{Float64}, chanfreqvec::Array{Float64,1}, flag::Array{Bool,4}, data::Array{Complex{Float32},4},
    numchan::Int64, times::Vector{Float64}; saveprefix="data_")

Plot complex visibilities against time and projected baseline length.
"""
function plotvis(uvw::Matrix{Float64}, chanfreqvec::Array{Float64,1}, flag::Array{Bool,4}, data::Array{Complex{Float32},4},
    numchan::Int64, times::Vector{Float64}; plotphases::Bool=false, saveprefix="data_")
    @info("Generating visibility plots...")
    uvwave = sqrt.(uvw[1,:].^2 .+ uvw[2,:].^2) / (299792458.0/mean(chanfreqvec)) / 1e9 # in units of Gλ

    maskindices = findall(isequal(true), flag)
    maskeddata = deepcopy(data)
    maskeddata[maskindices] .= NaN # assign NaN values to flagged visibilities

    #set pol colours
    colours = [[:red, :cyan], [:purple, :green]]
    labels = [["RR", "RL"], ["LR", "LL"]]

    # plot visibility amplitudes against projected baseline separation
    f = Figure(size=(900, 600))
    ax = Axis(f[1, 1], xlabel="Projected baseline separation (Gλ)", ylabel="Complex visibility amplitude (Jy)")
    for ii in 1:2
        for jj in 1:2
            scatter!(ax, uvwave, abs.(maskeddata[ii,jj,1,:]), color=colours[ii][jj], label=labels[ii][jj], markersize=1)
            if numchan > 1
                scatter!(ax, uvwave, abs.(maskeddata[ii,jj,2:end,:]'), color=colours[ii][jj], label="", markersize=1)
            end
        end
    end

    axislegend(ax, position=:rt)
    save(saveprefix*"visibilityamplitude_vs_baseline.png", f)

    # plot visibility phases against projected baseline separation
    if plotphases
        f = Figure(size=(900, 600))
        ax = Axis(f[1, 1], xlabel="Projected baseline separation (Gλ)", ylabel="Complex visibility phase (deg.)")
        for ii in 1:2
            for jj in 1:2
                scatter!(ax, uvwave, rad2deg.(angle.(maskeddata[ii,jj,1,:])), color=colours[ii][jj], label=labels[ii][jj], markersize=1)
                if numchan > 1
                    scatter!(ax, uvwave, rad2deg.(angle.(maskeddata[ii,jj,2:end,:]')), color=colours[ii][jj], label="", markersize=1)
                end
            end
        end

        axislegend(ax, position=:rt)
        save(saveprefix*"visibilityphase_vs_baseline.png", f)
    end

    @info("Plotted visibilities 🙆")
end

"""
    plotstationgains(h5file::String, scanno::Vector{Int32}, times::Vector{Float64}, exposure::Float64, stationnames::Vector{String3})

Plot complex station gains against time.
"""
function plotstationgains(h5file::String, scanno::Vector{Int32}, times::Vector{Float64}, exposure::Float64, stationnames::Vector{String3})
    @info("Plotting station gains against time...")
    fid = h5open(h5file, "r")

    # get unique scan numbers
    uniqscans = unique(scanno)

    # get unique times
    uniqtimes = unique(times)

    f = Figure(size=(900, 400))
    axphase1 = Axis(f[1, 1], ylabel="Phases (°)", title="Station gains (Pol1)")
    axamp1 = Axis(f[2, 1], xlabel="Relative time (hr)", ylabel="Amplitudes (Jy)")
    axphase2 = Axis(f[1, 2], title="Station gains (Pol2)")
    axamp2 = Axis(f[2, 2], xlabel="Relative time (hr)")

    # modify axis attributes
    hidexdecorations!(axphase1)
    hidexdecorations!(axphase2)
    hideydecorations!(axamp2, grid=false, ticks=false)
    hideydecorations!(axphase2, grid=false, ticks=false)

    for scan in uniqscans

        # determine indices of missing values
        actualtscanvec = unique(getindex(times, findall(scanno.==scan)))
    	actualtscanveclen = length(actualtscanvec)
	    idealtscanvec = collect(first(actualtscanvec):exposure:last(actualtscanvec))
	    idealtscanveclen = length(idealtscanvec)

        gterms = read(fid["stationgains"]["gjones_scan$(scan)"])
        #indexend = indexend + size(gterms)[3]

        # loop over time/row and apply gjones terms corresponding to each baseline
	    findnearest(A,x) = argmin(abs.(A .- x)) # define function to find nearest neighbour
        indvector = []
        for t in 1:actualtscanveclen
            idealtimeindex = findnearest(idealtscanvec, actualtscanvec[t])
            push!(indvector, idealtimeindex)
        end
            
        for ant in eachindex(stationnames)
            gpol1amp = abs.(gterms[1,1,indvector,ant]) # plot only the indices selected in the previous step
            gpol1phase = rad2deg.(angle.(gterms[1,1,indvector,ant]))
            gpol2amp = abs.(gterms[2,2,indvector,ant]) # plot only the indices selected in the previous step
            gpol2phase = rad2deg.(angle.(gterms[2,2,indvector,ant]))

            xvals = (actualtscanvec .- first(uniqtimes)) ./ 3600.0 # relative time in hours
            #if scan == 1
                lines!(axamp1, xvals, gpol1amp, ls=:solid, lw=1, color=ColorSchemes.mk_15[ant], label=stationnames[ant])
                lines!(axphase1, xvals, gpol1phase, ls=:solid, lw=1, color=ColorSchemes.mk_15[ant], label=stationnames[ant])

                lines!(axamp2, xvals, gpol2amp, ls=:solid, lw=1, color=ColorSchemes.mk_15[ant], label=stationnames[ant])
                lines!(axphase2, xvals, gpol2phase, ls=:solid, lw=1, color=ColorSchemes.mk_15[ant], label=stationnames[ant])
            #end
            #= else
                lines!(axamp1, xvals, gpol1amp, ls=:solid, lw=1, color=ColorSchemes.mk_15[ant])
                lines!(axphase1, xvals, gpol1phase, ls=:solid, lw=1, color=ColorSchemes.mk_15[ant])

                lines!(axamp2, xvals, gpol2amp, ls=:solid, lw=1, color=ColorSchemes.mk_15[ant])
                lines!(axphase2, xvals, gpol2phase, ls=:solid, lw=1, color=ColorSchemes.mk_15[ant])
            end =#
        end
        #indexstart = indexend + 1
       
    end

    linkxaxes!(axamp1, axphase1)
    linkxaxes!(axamp2, axphase2)
    linkyaxes!(axamp1, axamp2)
    linkyaxes!(axphase1, axphase2)

    f[1:2, 3] = Legend(f, axamp1, merge=true, unique=true, tellheight=true, tellwidth=true)

    close(fid) # close HDF5 file

    save("StationGains_vs_time.png", f)

    @info("Plotted station gains 🙆")
end