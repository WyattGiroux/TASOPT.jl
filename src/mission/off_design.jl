"""
    fly_off_design!(ac, mi, itermax, initeng, saveOffDesign)

`fly_off_design!` runs the aircraft through input off-design missions

!!! details "🔃 Inputs and Outputs"
**Inputs:**
- `ac::aircraft`: Aircraft with first mission being the design mission
- `mi::Int64`: Off design mission to run (Default: 1)
- `itermax::Int64`: Maximum iterations for sizing loop
- `initeng::Boolean`: Use design case as initial guess for engine state if true

**Outputs:**
- No explicit outputs. Computed quantities are saved to `par` arrays of `aircraft` model for the off design mission selected

"""
function fly_off_design!(ac, mi = 1; itermax = 35, initeng = true)

    pari = ac.pari
    parg = ac.parg
    parm = view(ac.parm, :, mi:mi)
    para = view(ac.para, :, :, mi:mi)
    pare = view(ac.pare, :, :, mi:mi)
    parad = ac.parad
    pared = ac.pared

    resetHXs(pare) #Reset heat exchanger parameters

    fuse = ac.fuselage
    wing = ac.wing
    htail = ac.htail

    time_propsys = 0.0

    tolerW = 1.0e-8
    errw   = 1.0

    fuse_tank = ac.fuse_tank #Unpack struct with tank parameters
    fuse = ac.fuselage 

#------ mission-varying excrescence factors disabled in this version
#-      ( also commented out in getparm.f )
#        para(iafexcdw,ip) = parm[imfexcdw]
#        para(iafexcdt,ip) = parm[imfexcdt]
#        para(iafexcdf,ip) = parm[imfexcdf]

    #Calculate sea level temperature corresponding to TO conditions
    altTO = parm[imaltTO] 
    T_std,_,_,_,_ = atmos(altTO/1e3)
    ΔTatmos = parm[imT0TO] - T_std #temperature difference such that T(altTO) = T0TO
    parm[imDeltaTatm] = ΔTatmos

    # Calculates surface velocities, boundary layer, wake 
    fusebl!(fuse, parm, para, ipcruise1)

#---- assume K.E., dissipation, drag areas will be the same for all points
    KAfTE   = para[iaKAfTE  , ipcruise1] # Kinetic energy area at T.E.
    DAfsurf = para[iaDAfsurf, ipcruise1] # Surface dissapation area 
    DAfwake = para[iaDAfwake, ipcruise1] # Wake dissapation area
    PAfinf  = para[iaPAfinf , ipcruise1] # Momentum area at ∞

    # Assume K.E., Disspation and momentum areas are const. for all mission points:
    para[iaKAfTE  , :] .= KAfTE
    para[iaDAfsurf, :] .= DAfsurf
    para[iaDAfwake, :] .= DAfwake
    para[iaPAfinf , :] .= PAfinf

# ===================================================================
# ---- max range and this mission range
    Rangemax = parg[igRange]
    Rangetot = parm[imRange]

#---- max TO weight
    WMTO = parg[igWMTO]

# ---- zero-fuel weight for this mission
    Wzero = WMTO-
          parg[igWfuel]-
          parg[igWpay]+
          parm[imWpay]

# ===================================================================
# ---- initial fuel and gross takeoff weight estimates from Breguet, R ~ ln(1+f)
    gmax = log(1.0 + parg[igWfuel]/Wzero)
    gmaxp = gmax * Rangetot/Rangemax
    Wfuel = (exp(gmaxp) - 1.0) * Wzero
    WTO = Wzero + Wfuel

    parm[imWfuel] = Wfuel
    parm[imWTO]   = WTO

#---- scale initial weight fractions by takeoff and descent weight ratios
    rTO = WTO/WMTO
    rDE = Wzero/(WMTO-parg[igWfuel])

    para[iafracW, ipstatic ] = parad[iafracW,ipstatic ]*rTO
    para[iafracW, iprotate ] = parad[iafracW,iprotate ]*rTO
    para[iafracW, iptakeoff] = parad[iafracW,iptakeoff]*rTO
    para[iafracW, ipcutback] = parad[iafracW,ipcutback]*rTO

    # Climb
    @inbounds for ip = ipclimb1:ipclimbn
          para[iafracW,ip] = parad[iafracW,ip] * rTO
    end
    # Cruise
    @inbounds for ip = ipcruise1:ipcruisen
          frac = float(ip       -ipcruise1)/
                float(ipcruisen-ipcruise1)
          rCR = rTO*(1.0-frac) + rDE*frac
          para[iafracW,ip] = parad[iafracW,ip] * rCR
    end
    # Descent
    para[iafracW,ipdescent1:ipdescentn] .= parad[iafracW,ipdescent1:ipdescentn] .* rDE
    para[iagamV,:] .= parad[iagamV,:]

#---- estimate takeoff speed and set V,Re over climb and descent
#-    (needed to start trajectory integration)
    ip = iptakeoff
    VTO = pared[ieu0,ip] * sqrt(pared[ierho0,ip]/pare[ierho0,ip])
    ReTO = VTO*pare[ierho0,ip]/pare[iemu0,ip]

    ip = ipcruise1
    VCR = pared[ieu0,ip]
    ReCR = parad[iaReunit,ip]

    for ip = iprotate: ipclimb1
      pare[ieu0,ip] = VTO
      para[iaReunit,ip] = ReTO
    end
    for ip = ipclimb1+1 : ipclimbn
      frac = float(ip-ipclimb1) / float(ipclimbn-ipclimb1)
      V  =  VTO*(1.0-frac) +  VCR*frac
      Re = ReTO*(1.0-frac) + ReCR*frac
      pare[ieu0,ip] = V
      para[iaReunit,ip] = Re
    end
    for ip = ipdescent1: ipdescentn
      frac = float(ip-ipdescent1) / float(ipdescentn-ipdescent1)
      V  =  VTO*frac +  VCR*(1.0-frac)
      Re = ReTO*frac + ReCR*(1.0-frac)
      pare[ieu0,ip] = V
      para[iaReunit,ip] = Re
    end

    if initeng == 1
#----- use design case as initial guess for engine state
          for ip = 1: iptotal
                for ie = 1: ietotal
                      pare[ie,ip] = pared[ie,ip]
                end
          end
    end
  
    for ip = ipstatic: ipdescentn
      para[iaCfnace,ip] = parad[iaCfnace,ip]
    end

#--------------------------------------------------------------------------
#---- set wing pitching moment constants
    b  = wing.layout.span
    bs = wing.layout.break_span
    bo = wing.layout.root_span
    sweep = wing.layout.sweep
    Xaxis = wing.layout.spar_box_x_c
    λs = wing.inboard.λ
    λt = wing.outboard.λ
    AR = wing.layout.AR
    fLo =  wing.fuse_lift_carryover
    fLt =  wing.tip_lift_loss

    ip = iptakeoff
    cmpo = para[iacmpo,ip]
    cmps = para[iacmps,ip]
    cmpt = para[iacmpt,ip]
    γt = wing.outboard.λ*para[iarclt,ip]
    γs = wing.inboard.λ*para[iarcls,ip]

    CMw0, CMw1 = surfcm(b, bs, bo, sweep, Xaxis,
                            λt,λs,γt,γs, 
                            AR,fLo,fLt,cmpo,cmps,cmpt)

    para[iaCMw0, ipstatic:ipclimb1] .= CMw0
    para[iaCMw1, ipstatic:ipclimb1] .= CMw1

    ip = ipcruise1
    cmpo, cmps, cmpt = para[iacmpo, ip], para[iacmps, ip], para[iacmpt, ip]

    γt = wing.outboard.λ*para[iarclt, ip]
    γs = wing.inboard.λ*para[iarcls, ip]
    
    CMw0, CMw1 = surfcm(b, bs, bo, sweep, Xaxis,
                      λt,λs,γt,γs, 
                      AR,fLo,fLt,cmpo,cmps,cmpt)
    
    para[iaCMw0, ipclimb1+1:ipdescentn-1] .= CMw0
    para[iaCMw1, ipclimb1+1:ipdescentn-1] .= CMw1
    
    ip = ipdescentn
    cmpo, cmps, cmpt = para[iacmpo, ip], para[iacmps, ip], para[iacmpt, ip]
    γt = wing.outboard.λ*para[iarclt, ip]
    γs = wing.inboard.λ*para[iarcls, ip]

    CMw0, CMw1 = surfcm(b, bs, bo, sweep, Xaxis,
                      λt,λs,γt,γs, 
                      AR,fLo,fLt,cmpo,cmps,cmpt)

    para[iaCMw0, ipdescentn] = CMw0
    para[iaCMw1, ipdescentn] = CMw1

#---- tail pitching moment constants
    bh      = htail.layout.span
    boh     = htail.layout.root_span
    sweeph  = htail.layout.sweep
    λh      = htail.outboard.λ
    ARh     = htail.layout.AR
    fLoh = 0.
    fLth = fLt
    cmph = 0.

    CMh0, CMh1 = surfcm(bh, boh, boh, sweeph, Xaxis, λh, 1.0, λh, 1.0,
    ARh, fLoh, fLth, 0.0, 0.0, 0.0)

    para[iaCMh0, :] .= CMh0
    para[iaCMh1, :] .= CMh1

    # Initialize previous weight iterations
    WTO1, WTO2, WTO3 = zeros(Float64, 3) #1st-previous to 3rd previous iteration weight for convergence criterion

#---- no convergence yet
    Lconv = false

# -------------------------------------------------------    
#                   Weight loop
# -------------------------------------------------------    
  @inbounds for  iterw = 1:itermax

    if iterw == itermax
        println("Reached max iterations in weight sizing loop!")
    end

    rlx = 1.0
    if (iterw > itermax-5)
          rlx = 0.5
    end

    set_ambient_conditions!(ac, ipcruise1)

    if (pari[iifwing] == 0) #If fuel is stored in the fuselage
        #Analyze pressure evolution in tank and store the vented mass flow rate
        _, _, _, _, _, _, _, Mvents, _, _ = CryoTank.analyze_TASOPT_tank(ac, fuse_tank.t_hold_orig, fuse_tank.t_hold_dest, mi)
        parm[imWfvent] = Mvents[end] * gee #Store vented weight
    end

    # Calling mission
    time_propsys += mission!(pari, parg, parm, para, pare, fuse, wing, htail, ac.vtail, false, calculate_cruise = true) #Calculate start of cruise too
    # println(parm[imWfuel,:])

    #TODO add heat exchanger models once HX parameters are stored
    #HXOffDesign!(HeatExchangers, pare, pari)
    
#-------------------------------------------------------------------------

# Convergence tests
    
    WTO = parm[imWTO]
    errw1 = (WTO - WTO1)/WTO
    errw2 = (WTO - WTO2)/WTO
    errw3 = (WTO - WTO3)/WTO

    errw = max(abs(errw1), abs(errw2), abs(errw3))

    if (errw <= tolerW) 
          Lconv = true

          break
    end

#-----------------------------------------------------------------
#---- set previous-iteration weights for next iteration
    WTO3 = WTO2
    WTO2 = WTO1
    WTO1 = parm[imWTO]

    end

return 
end