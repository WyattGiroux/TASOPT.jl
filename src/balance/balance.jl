"""
      balance(ac, imission, ip, rfuel, rpay, ξpay, itrim)

Makes one of three (or none) changes to achieve pitch trim
calculates resulting CG, CP, NP locations.

Inputs:
- `ac::aircraft`: structure with aircraft parameters
- `imission::Int64`: mission index (1 is design mission)
- `ip::Int64`: mission point index
- `rfuel`    fuel fraction
- `rpay`     payload fraction Wpay_actual/Wpay_MTOW
- `ξpay`    partial-payload packing location
    * = 0.0   all the way in front  of cabin
    * = 0.5   all the way in middle of cabin
    * = 1.0   all the way in back   of cabin
- `itrim`      = 0  no changes
    * = 1  adjust CLh   (horizontal tail cl)
    * = 2  adjust Sh    (horizontal tail area)
    * = 3  adjust xwbox (wing box location)

Outputs: 
No direct outputs. Fields in `ac` are modified.
"""
function balance(ac, imission, ip, rfuel, rpay, ξpay, itrim)
      #Unpack aircraft
      pari, parg, parm, para, pare, fuse, fuse_tank, wing, htail, vtail = unpack_ac(ac, imission, ip = ip)

      iengloc = pari[iiengloc]

      # Unpack weights
      Wpay = parg[igWpay]
      Wfuel = parg[igWfuel]
      Wfuse = fuse.weight
      Wwing = wing.weight
      Wstrut = wing.strut.weight
      Whtail = htail.weight
      Wvtail = vtail.weight
      Weng = parg[igWeng]

      xWfuel = parg[igxWfuel]

      Wtesys = parg[igWtesys]
      xWtesys = parg[igxWtesys]

      Wftank = parg[igWftank]
      xWftank = parg[igxWftank]

      nftanks = pari[iinftanks] #number of fuel tanks in fuselage
      lftank = parg[iglftank]

      # Use weight fractions to calcualte weights of subsystems
      Whpesys = parg[igWMTO] * fuse.HPE_sys.W
      Wlgnose = parg[igWMTO] * parg[igflgnose]
      Wlgmain = parg[igWMTO] * parg[igflgmain]

      xcabin,lcabin = cabin_centroid(nftanks,fuse,parg[igxftankaft],lftank)
      
      xpay = xcabin + (ξpay - 0.5) * lcabin * (1.0 - rpay)

      xwbox = wing.layout.box_x

      rfuelF, rfuelB, rpayF, rpayB, xcgF, xcgB = cglpay(ac)

      #---- wing centroid offset from wingbox, assumed fixed in CG calculations
      dxwing = wing.layout.x - wing.layout.box_x

      #---- main LG offset from wingbox, assumed fixed in CG calculations
      dxlg = xcgB + parg[igdxlgmain] - wing.layout.box_x

      S = wing.layout.S
      Sh = htail.layout.S
      co = wing.layout.root_chord
      coh = htail.layout.root_chord
      xhbox = htail.layout.box_x

      cma = wing.mean_aero_chord

      #---- for better convergence, 
      #      will assume that HT weight will scale with its area
      Sh1 = Sh

      #---- total weight, weight moment, and derivatives
      W = rpay * Wpay +
          rfuel * Wfuel +
          Wfuse +
          Wtesys +
          Wftank +
          Wwing +
          Wstrut +
          Whtail * Sh / Sh1 +
          Wvtail +
          Weng +
          Whpesys +
          Wlgnose +
          Wlgmain

      #  println("rpay = $rpay, rufel = $rfuel;
      #   rpay *Wpay  = $(rpay *Wpay ) 
      #  rfuel*Wfuel = $(rfuel*Wfuel ) 
      #  Wfuse  = $(Wfuse  ) 
      #  Wtesys = $(Wtesys ) 
      #  Wftank = $(Wftank ) 
      #  Wwing  = $(Wwing  ) 
      #  Wstrut = $(Wstrut ) 
      #  Whtail*Sh/Sh1 = $(Whtail*Sh/Sh1) 
      #  Wvtail  = $(Wvtail  ) 
      #  Weng    = $(Weng    ) 
      #  Whpesys = $(Whpesys ) 
      #  Wlgnose = $(Wlgnose ) 
      #  Wlgmain = $(Wlgmain )")

      W_Sh = Whtail / Sh1

      #Calcualte fuel moment and derivaties wrt to wing box location 
      if (pari[iifwing] == 0) #If fuel is stored in the fuselage
            xWfuel = rfuel * xWfuel
            xWfuel_xwbox = 0.0
      else
            xWfuel = rfuel * xWfuel
            xWfuel_xwbox = rfuel * Wfuel
      end

      xW = rpay * Wpay * xpay +
           xWfuel +
           fuse.moment + xWtesys + xWftank +
           Wwing * wing.layout.box_x + wing.dxW +
           Wstrut * wing.layout.box_x + wing.strut.dxW +
           (Whtail * htail.layout.box_x + htail.dxW) * Sh / Sh1 +
           Wvtail * vtail.layout.box_x + vtail.dxW +
           Weng * parg[igxeng] +
           Whpesys * fuse.HPE_sys.r.x +
           Wlgnose * parg[igxlgnose] +
           Wlgmain * (wing.layout.box_x + dxlg)

      xW_xwbox = xWfuel_xwbox + Wwing + Wstrut + Wlgmain

      xW_Sh = (Whtail * htail.layout.box_x + htail.dxW) / Sh1

      #---- total aero moment and derivatives
      CMw0 = para[iaCMw0]
      CMw1 = para[iaCMw1]
      CMh0 = para[iaCMh0]
      CMh1 = para[iaCMh1]
      CL = para[iaCL]
      CLh = para[iaCLh]
      # println("before itrim $(para[iaCLh]), CL = $CL")
      CMVf1 = parg[igCMVf1]
      CLMf0 = parg[igCLMf0]

      cCM = co * CMw0 + (co * CMw1 - xwbox) * (CL - CLh * Sh / S) +
            coh * CMh0 * Sh / S + (coh * CMh1 - xhbox) * CLh * Sh / S +
            CMVf1 * (CL - CLMf0) / S

      cCM_xwbox = -(CL - CLh * Sh / S)
      cCM_Sh = (co * CMw1 - xwbox) * (-CLh / S) +
               coh * CMh0 / S + (coh * CMh1 - xhbox) * CLh / S
      cCM_CLh = (co * CMw1 - xwbox) * (-Sh / S) +
                (coh * CMh1 - xhbox) * Sh / S

      #---- current CP and CG location
      #      xCP = -cCM/CL
      #      xCG = xW/W

      #---- total-moment residual
      Res = cCM / CL + xW / W                 # Eq. 300
      Res_CLh = cCM_CLh / CL
      Res_Sh = cCM_Sh / CL + xW_Sh / W - (xW / W^2) * W_Sh
      Res_xwbox = cCM_xwbox / CL + xW_xwbox / W

      #      r[1] = Res
      #      a[1,1] = Res_CLh
      #      a[1,2] = Res_Sh
      #      a[1,3] = Res_xwbox

      #---- drive to Res=0 (pitch trim) by one of three changes...

      if (itrim == 1)
            #----- ... adjust horizontal tail CLh
            delCLh = -Res / Res_CLh
            CLh = CLh + delCLh
            #  println("inside itrim = 1: $delCLh, $CLh")
            cCM = cCM + cCM_CLh * delCLh
            para[iaCLh] = CLh

      elseif (itrim == 2)
            #----- ... adjust horizontal tail area
            delSh = -Res / Res_Sh
            Sh = Sh + delSh
            cCM = cCM + cCM_Sh * delSh
            xW = xW + xW_Sh * delSh

            htail.layout.S = Sh

      elseif (itrim == 3)
            #----- ... adjust wing box location
            delxwbox = -Res / Res_xwbox
            xwbox = xwbox + delxwbox
            cCM = cCM + cCM_xwbox * delxwbox
            xW = xW + xW_xwbox * delxwbox

            wing.layout.box_x = xwbox
            wing.layout.x = xwbox + dxwing

      end

      #---- calculate neutral point
      dCLhdCL = parg[igdCLhdCL]

      dCLndCL = parg[igdCLndCL]
      neng = parg[igneng]
      xeng = parg[igxeng]
      dfan = parg[igdfan]
      Afan = 0.25 * pi * dfan^2
      xengcp = xeng - 0.25 * dfan

      xNP = (co * CMw1 - xwbox) * (dCLhdCL * Sh / S - 1.0) -
            (coh * CMh1 - xhbox) * dCLhdCL * Sh / S -
            CMVf1 / S -
            neng * xengcp * dCLndCL * Afan / S
      xNP_xwbox = -(dCLhdCL * Sh / S - 1.0)
      xNP_Sh = (co * CMw1 - xwbox) * dCLhdCL / S -
               (coh * CMh1 - xhbox) * dCLhdCL / S
      xNP_CLh = 0.0

      #---- x locations after one of the trim changes
      #-     (xCP,xCG will be equal if moments are linear)
      xCP = -cCM / CL
      xCG = xW / W

      #---- component pitching moments
      #      cCM  = co *CMw0      + (co *CMw1 - xwbox)*(CL - CLh*Sh/S) - xref*CL
      #     &     + coh*CMh0*Sh/S + (coh*CMh1 - xhbox)*      CLh*Sh/S
      #     &     + CMVf1*(CL-CLMf0)/S
      #
      #      cCM_CL  = (co*CMw1  - xwbox - xref)*(1.0 - CLh_CL*Sh/S)
      #     &        + (coh*CMh1 - xhbox - xref)*CLh_CL*Sh/S

      #     CMwing = (co *CMw0      + (co *CMw1-xwbox-xCG)*(CL-CLh*Sh/S))/cma
      #     CMtail = (coh*CMh0*Sh/S + (coh*CMh1-xhbox-xCG)*    CLh*Sh/S )/cma
      #     CMfuse = CMVf1*(CL-CLMf0)/(S*cma)

      #---- store results for returning
      #      para[iaCMwing] = CMwing
      #      para[iaCMtail] = CMtail
      #      para[iaCMfuse] = CMfuse

      para[iaxCG] = xCG
      para[iaxCP] = xCP
      para[iaxNP] = xNP

      return
end # balance


"""
Sets horizontal tail area and wing position to simultaneously:

1) Meet pitch trim requirement with forward CG
2) Meet stability requirement with aft CG

Calculates resulting CG, CP, NP locations

Inputs:  
      
- `ac`       aircraft object
- `parg[.]`  geometry parameter array
- `paraF[.]` aero parameter array for fwdCG case
- `paraB[.]` aero parameter array for aft CG case
- `paraC[.]` aero parameter array for cruise tail CL case

Outputs: 
No direct outputs. Fields in `ac` are modified.
"""
function htsize(ac, paraF, paraB, paraC)
      #TODO find a way to remove the para inputs and use ac instead
      pari, parg, fuse, fuse_tank, wing, htail, vtail = unpack_ac_components(ac)

      itmax = 10
      toler = 1.0e-7

      r = zeros(Float64, 2)
      a = zeros(Float64, (2, 2))

      sweep = wing.layout.sweep
      cosL = cosd(sweep)

      #---- set CG limits with worst-case payload arrangements
      rfuelF, rfuelB, rpayF, rpayB, xcgF, xcgB = cglpay(ac)

      rpayC = 1.0

      parg[igxCGfwd] = xcgF
      parg[igxCGaft] = xcgB

      CLF = paraF[iaclpmax] * cosL^2
      CLhF = htail.CL_max_fwd_CG

      CLC = paraC[iaCL]
      CLhC = parg[igCLhspec]

      SM = htail.SM_min
      cma = wing.mean_aero_chord

      # Unpack flags
      iengloc = pari[iiengloc]  # Engine location 
      iHTsize = htail.size
      ixwmove = htail.move_wingbox
      # Unpack Weights
      Wpay = parg[igWpay]
      Wfuel = parg[igWfuel]
      Wfuse = fuse.weight
      Wwing = wing.weight
      Wstrut = wing.strut.weight
      Whtail = htail.weight
      Wvtail = vtail.weight
      Weng = parg[igWeng]

      xWfuel = parg[igxWfuel]

      # Wtshaft = parg[igWtshaft] 
      # Wgen    = parg[igWgen   ] 
      # Winv    = parg[igWinv   ] 
      # Wmot    = parg[igWmot   ] 
      # Wfan    = parg[igWfan   ] 

      Wtesys = parg[igWtesys]
      xWtesys = parg[igxWtesys]

      nftanks = pari[iinftanks]
      lftank = parg[iglftank]
      Wftank = parg[igWftank]
      xWftank = parg[igxWftank]

      Whpesys = parg[igWMTO] * fuse.HPE_sys.W
      Wlgnose = parg[igWMTO] * parg[igflgnose]
      Wlgmain = parg[igWMTO] * parg[igflgmain]

      xWfuse = fuse.moment

      dxWwing = wing.dxW
      dxWstrut = wing.strut.dxW
      dxWhtail = htail.dxW
      dxWvtail = vtail.dxW

      xeng = parg[igxeng]
      xlgnose = parg[igxlgnose]

      # xtshaft = parg[igxtshaft ]
      # xgen    = parg[igxgen    ]
      # xinv    = parg[igxinv    ]
      # xmot    = parg[igxmot    ]
      # xfan    = parg[igxfan    ]
      xftank = parg[igxftank]

      # Calculate x location of cabin centroid and length of cabin
      xcabin,lcabin = cabin_centroid(nftanks,fuse,parg[igxftankaft],lftank)

      #---- payload CG locations for forward and aft CG locations
      xpayF = xcabin + (0.0 - 0.5) * lcabin * (1.0 - rpayF)
      xpayB = xcabin + (1.0 - 0.5) * lcabin * (1.0 - rpayB)
      xpayC = xcabin

      xwbox = wing.layout.box_x

      #---- wing centroid offset from wingbox, assumed fixed in CG calculations
      dxwing = wing.layout.x - wing.layout.box_x

      #---- main LG offset from wingbox, assumed fixed in CG calculations
      dxlg = parg[igxCGaft] + parg[igdxlgmain] - wing.layout.box_x

      S = wing.layout.S
      Sh = htail.layout.S
      co = wing.layout.root_chord
      coh = htail.layout.root_chord
      xhbox = htail.layout.box_x
      xvbox = vtail.layout.box_x

      WfuelC = paraC[iafracW] * parg[igWMTO] -
               rpayC * Wpay -
               Wfuse -
               Wtesys -
               Wftank -
               Wwing -
               Wstrut -
               Whtail -
               Wvtail -
               Weng -
               Whpesys -
               Wlgnose -
               Wlgmain

      rfuelC = WfuelC / Wfuel


      #---- for better convergence, 
      #      will assume that HT weight and moment will scale with its area
      Sh_o = Sh
      Whtail_o = Whtail
      dxWhtail_o = dxWhtail

      #c      do 100 iter = 0, -2, -1

      xWF, xWB, xWc = 0.0, 0.0, 0.0
      WF, WB, Wc = 0.0, 0.0, 0.0
      dmax = 0.0

      @inbounds for iter = 1:itmax

            # HT weight, moment and derivatives ∂Whtail/∂Sh
            Whtail = (Whtail_o / Sh_o) * Sh
            Whtail_Sh = Whtail_o / Sh_o

            dxWhtail = (dxWhtail_o / Sh_o) * Sh
            dxWhtail_Sh = dxWhtail_o / Sh_o

            #---- empty (no fuel, no payload) weight
            We = Wfuse +
                 Wwing +
                 Wtesys +
                 Wftank +
                 Wstrut +
                 Whtail +
                 Wvtail +
                 Weng +
                 Whpesys +
                 Wlgnose +
                 Wlgmain

            We_Sh = Whtail_Sh

            #---- empty (no-payload) weight moment
            xWe = xWfuse + xWtesys + xWftank +
                  Wwing * xwbox + dxWwing +
                  Wstrut * xwbox + dxWstrut +
                  Whtail * xhbox + dxWhtail +
                  Wvtail * xvbox + dxWvtail +
                  Weng * xeng +
                  Whpesys * fuse.HPE_sys.r.x +
                  Wlgnose * xlgnose +
                  Wlgmain * (xwbox + dxlg)

            xWe_Sh = Whtail_Sh * xhbox + dxWhtail_Sh
            xWe_xw = Wwing +
                     Wstrut +
                     Wlgmain


            #---- total weight at forward and aft CG limits, and cruise
            WF = We + rfuelF * Wfuel + rpayF * Wpay
            WB = We + rfuelB * Wfuel + rpayB * Wpay
            WC = We + rfuelC * Wfuel + rpayC * Wpay

            WF_Sh = We_Sh
            WB_Sh = We_Sh
            WC_Sh = We_Sh

            #---- total weight moment at forward and aft CG limits
            if pari[iifwing] == 0
                  xWfuel_xw = 0.0
            else
                  xWfuel_xw = Wfuel
            end
            xWF = xWe + rpayF * Wpay * xpayF + rfuelF * xWfuel
            xWB = xWe + rpayB * Wpay * xpayB + rfuelB * xWfuel
            xWC = xWe + rpayC * Wpay * xpayC + rfuelC * xWfuel

            xWF_xw = xWe_xw + rfuelF * xWfuel_xw
            xWB_xw = xWe_xw + rfuelB * xWfuel_xw
            xWC_xw = xWe_xw + rfuelC * xWfuel_xw

            xWF_Sh = xWe_Sh
            xWB_Sh = xWe_Sh
            xWC_Sh = xWe_Sh

            if (iHTsize == 1)
                  #----- fix HT volume (Section 2.12.1 of TASOPT docs)
                  lhtail = htail.layout.x - (xwbox + dxwing)
                  lhtail_xw = -1.0

                  Vh = htail.volume     # Tail volume is specified here!
                  Sh = Vh * S * cma / lhtail # Corresponding tail surf area

                  r[1] = Sh * lhtail - Vh * S * cma  # This is 0 (residual is 0 ∵ Vh = Sh*lh/(S*cma))
                  a[1, 1] = lhtail
                  a[1, 2] = Sh * lhtail_xw

            else
                  #----- set HT area by pitch trim power at forward CG case
                  CMw0 = paraF[iaCMw0]
                  CMw1 = paraF[iaCMw1]
                  CMh0 = paraF[iaCMh0]
                  CMh1 = paraF[iaCMh1]
                  CMVf1 = parg[igCMVf1]
                  CLMf0 = parg[igCLMf0]
                  CL = CLF
                  CLh = CLhF

                  cCM = co * CMw0 + (co * CMw1 - xwbox) * (CL - CLh * Sh / S) +
                        coh * CMh0 * Sh / S + (coh * CMh1 - xhbox) * CLh * Sh / S +
                        CMVf1 * (CL - CLMf0) / S
                  cCM_xw = -(CL - CLh * Sh / S)
                  cCM_Sh = (co * CMw1 - xwbox) * (-CLh / S) +
                           coh * CMh0 / S + (coh * CMh1 - xhbox) * CLh / S

                  # Residual eqn ℛₘ that is equivalent to CP and CG coinciding
                  r[1] = cCM / CL + xWF / WF
                  a[1, 1] = cCM_Sh / CL + xWF_Sh / WF - (xWF / WF^2) * WF_Sh  # ∂ℛₘ/∂Sₕ
                  a[1, 2] = cCM_xw / CL + xWF_xw / WF                     # ∂ℛₘ/∂xw

                  # +--                 --+  +-   -+      +-   -+
                  # | ∂ℛₘ/∂Sₕ    ∂ℛₘ/∂xw |  | δSₕ  |      | ℛₘ |
                  # |                     |  |     |  =   |     |
                  # |                     |  | δxw |      |     |
                  # +--                 --+  +-   -+      +-   -+

            end


            if (ixwmove == 0)
                  #----- fix wing location
                  r[2] = 0.0
                  a[2, 1] = 0.0
                  a[2, 2] = 1.0

            elseif (ixwmove == 1)
                  #----- set wing location to get CLh=CLhspec in cruise
                  CMw0 = paraC[iaCMw0]
                  CMw1 = paraC[iaCMw1]
                  CMh0 = paraC[iaCMh0]
                  CMh1 = paraC[iaCMh1]
                  CMVf1 = parg[igCMVf1]
                  CLMf0 = parg[igCLMf0]
                  CL = CLC
                  CLh = CLhC  #CLh is specified here

                  cCM = co * CMw0 + (co * CMw1 - xwbox) * (CL - CLh * Sh / S) +
                        coh * CMh0 * Sh / S + (coh * CMh1 - xhbox) * CLh * Sh / S +
                        CMVf1 * (CL - CLMf0) / S
                  #c   &        - neng*xenginl*CLn*Afan/S
                  cCM_xw = -(CL - CLh * Sh / S)
                  cCM_Sh = (co * CMw1 - xwbox) * (-CLh / S) +
                           coh * CMh0 / S + (coh * CMh1 - xhbox) * CLh / S

                  r[2] = cCM / CL + xWC / WC
                  a[2, 1] = cCM_Sh / CL + xWC_Sh / WC - (xWC / WC^2) * WC_Sh
                  a[2, 2] = cCM_xw / CL + xWC_xw / WC

            elseif (ixwmove == 2)
                  #----- set wing location by stability margin at aft-CG case
                  CMw1 = paraB[iaCMw1]
                  CMh1 = paraB[iaCMh1]
                  CMVf1 = parg[igCMVf1]
                  dCLhdCL = parg[igdCLhdCL]

                  dCLndCL = parg[igdCLndCL]
                  neng = parg[igneng]
                  xeng = parg[igxeng]
                  dfan = parg[igdfan]
                  Afan = 0.25 * pi * dfan^2
                  xengcp = xeng - 0.25 * dfan
                  # Eqn 297, 298:
                  xNP = (co * CMw1 - xwbox) * (dCLhdCL * Sh / S - 1.0) -
                        (coh * CMh1 - xhbox) * dCLhdCL * Sh / S -
                        CMVf1 / S -
                        neng * xengcp * dCLndCL * Afan / S  #∂CLnace/∂CL moments caused by engines

                  xNP_xw = -(dCLhdCL * Sh / S - 1.0)
                  xNP_Sh = (co * CMw1 - xwbox) * dCLhdCL / S -
                           (coh * CMh1 - xhbox) * dCLhdCL / S

                  # ℛsh(xw, Sh) ≡ xCG - xNP + fSM*cma 
                  # → must have some min static pitch stability i.e. xCG in front of xNP by a static margin
                  r[2] = xWB / WB - xNP + SM * cma
                  a[2, 1] = xWB_Sh / WB - xNP_Sh - (xWB / WB^2) * WB_Sh
                  a[2, 2] = xWB_xw / WB - xNP_xw

                  # +-                   -+  +-   -+      +-   -+
                  # | ∂ℛₘ/∂Sₕ    ∂ℛₘ/∂xw |  | δSₕ  |      | ℛₘ |
                  # |                     |  |     |  =   |     |
                  # | ∂ℛsh/∂Sₕ   ∂ℛsh/∂xw|  | δxw |      |ℛsh |
                  # +-                   -+  +-   -+      +-   -+

            end

            det = a[1, 1] * a[2, 2] - a[1, 2] * a[2, 1]
            d1 = (r[1] * a[2, 2] - a[1, 2] * r[2]) / det
            d2 = (a[1, 1] * r[2] - r[1] * a[2, 1]) / det

            dSh = -d1
            dxw = -d2

            Sh = Sh + dSh
            xwbox = xwbox + dxw

            dmax = max(abs(dxw) / cma, abs(dSh) / (0.2 * S))
            if (dmax < toler)
                  break
            end

      end #end for loop iter
      dmax > toler && println("HTSIZE: Pitch not converged. dxwbox,dSh = $dxw, $dSh")


      #---- set converged results
      htail.layout.S = Sh
      #c    parg[igWhtail] = (Whtail_o/Sh_o) * Sh
      wing.layout.box_x = xwbox
      wing.layout.x = xwbox + dxwing

      #Move engine as well to maintain the input offset distance from engine to wing box
      dxeng2wbox = parg[igdxeng2wbox]
      parg[igxeng] = xwbox - dxeng2wbox

      if (iHTsize == 1)
            #----- for fixed HT area, find minimum required CLh for foward-CG trim
            CMw0 = paraF[iaCMw0]
            CMw1 = paraF[iaCMw1]
            CMh0 = paraF[iaCMh0]
            CMh1 = paraF[iaCMh1]
            CMVf1 = parg[igCMVf1]
            CLMf0 = parg[igCLMf0]
            CL = CLF
            CLh = CLhF
            cCM = co * CMw0 + (co * CMw1 - xwbox) * (CL - CLh * Sh / S) +
                  coh * CMh0 * Sh / S + (coh * CMh1 - xhbox) * CLh * Sh / S +
                  CMVf1 * (CL - CLMf0) / S
            cCM_CLh = (co * CMw1 - xwbox) * (-Sh / S) +
                      (coh * CMh1 - xhbox) * Sh / S

            res = cCM / CL + xWF / WF
            res_CLh = cCM_CLh / CL
            dCLh = -res / res_CLh
            CLh = CLh + dCLh
            htail.CL_max_fwd_CG = CLh
      end


      return
end # htsize


"""
Calculates min and max xCG locations from payload extremes,
and corresponding payload fractions.

`rfuelF`,`rpayF`   give most-forward  location `xcgF`
`rfuelB`,`rpayB`   give most-rearward location `xcgB`

This version always returns `rfuelF` = `rfuelB` = 0.0
which gives an explicit solution for `rpayF`,`rpayB`.

The alternative 2D search for `rfuel`,`rpay` is kinda ugly, 
and unwarranted in practice.
"""
function cglpay(ac)
      pari, parg, fuse, fuse_tank, wing, htail, vtail = unpack_ac_components(ac)

      Wpay = parg[igWpay]
      Wfuel = parg[igWfuel]
      Wpay = parg[igWpay]
      Wfuel = parg[igWfuel]
      Wfuse = fuse.weight
      Wwing = wing.weight
      Wstrut = wing.strut.weight
      Whtail = htail.weight
      Wvtail = vtail.weight
      Weng = parg[igWeng]

      xWfuel = parg[igxWfuel]

      Wtesys = parg[igWtesys]
      #      xWtesys = parg[igxWtesys]

      nftanks = pari[iinftanks]
      lftank = parg[iglftank]
      Wftank = parg[igWftank]
      #      xWftank = parg[igxWftank]

      Whpesys = parg[igWMTO] * fuse.HPE_sys.W
      Wlgnose = parg[igWMTO] * parg[igflgnose]
      Wlgmain = parg[igWMTO] * parg[igflgmain]

      xcabin,lcabin = cabin_centroid(nftanks,fuse,parg[igxftankaft],lftank)
      delxw = wing.layout.x - wing.layout.box_x

      #---- zero fuel is assumed to be worst case forward and full fuel worst case aft
      rfuel = 0.0

      # See Eqn 283 in TASOPT documentation

      We = rfuel * Wfuel +
           Wfuse +
           Wtesys +
           Wftank +
           Wwing +
           Wstrut +
           Whtail +
           Wvtail +
           Weng +
           Whpesys +
           Wlgnose +
           Wlgmain

      xWe = rfuel * xWfuel +
            fuse.moment + parg[igxWtesys] + parg[igxWftank] +
            Wwing * wing.layout.box_x + wing.dxW +
            Wstrut * wing.layout.box_x + wing.strut.dxW +
            Whtail * htail.layout.box_x + htail.dxW +
            Wvtail * vtail.layout.box_x + vtail.dxW +
            Weng * parg[igxeng] +
            Whpesys * fuse.HPE_sys.r.x +
            Wlgnose * parg[igxlgnose] +
            Wlgmain * (wing.layout.box_x + delxw + parg[igdxlgmain])


      # Some derivation here:        
      #   xpay = xcabin + (ξpay-0.5)*lcabin*(1.0-rpay)  [1]                                   
      #    W =   We +      Wpay*rpay + rf* Wf           [2]                         
      #   xW =  xWe + xpay*Wpay*rpay + rf*xWf           [3]                         
      #  xcg = xW/W                                     [4]
      #
      #  Now, xpay*Wpay*rpay = (xcabin + (ξpay-0.5)*lcabin)*Wpay*rpay - (ξpay-0.5)*lcabin*Wpay*rpay²
      #                      =               a₁                 *rpay +            a₂         *rpay²
      #
      #  ∴ xW = a₀ + a₁rpay + a₂rpay² ;  a₀ = xWe + rf*xWf
      #     W = b₀ + b₁rpay           ;  b₀ =  We + rf* Wf, b₁ = Wpay

      # Explanation:
      #  now we find the stationary points of 
      #  xcg wrt to rpay. xcg = xW/W by setting 
      #  ∂xcg/∂rpay = 0
      #  this simplifies to a quadratic equation that gives rpay for the 
      #  min and max values of xcg
      #
      #  Repeat this for ξ = 0 and ξ = 1 (passengers all in front vs all in the back)
      #
      ξ = [0.0, 1.0]
      sgn = [-1.0, 1.0]

      xftank = parg[igxWftank] / Wftank
      if pari[iifwing] == 1 #Fuel is in wings
            rf = [0.0, 0.0]
      elseif xftank < xcabin
            rf = [1.0, 0.0]
      else
            rf = [0.0, 1.0]
      end
      
      rpay = zeros(Float64, 2)
      xcg = zeros(Float64, 2)

      @inbounds for i = 1:2

            a0 = xWe + rf[i] * xWfuel
            b0 = We + rf[i] * Wfuel
            b1 = Wpay

            a1 = (xcabin + (ξ[i] - 0.5) * lcabin) * Wpay
            a2 = -(ξ[i] - 0.5) * lcabin * Wpay

            AA = a2 * b1
            BB = 2.0 * a2 * b0
            CC = a1 * b0 - a0 * b1

            if BB^2 - 4.0 * AA * CC ≤ 0.0
                  println("a2 = $a2 ; b0^2 = $(b0^2); a0 = $(a0); b1^2 = $(b1^2); a1 = $(a1)")
            end

            rpay[i] = (-BB - sgn[i] * sqrt(BB^2 - 4.0 * AA * CC)) * 0.5 / AA

            xpay = xcabin + (ξ[i] - 0.5) * lcabin * (1.0 - rpay[i])
            W = Wpay * rpay[i] + We + rf[i] * Wfuel
            xW = xpay * Wpay * rpay[i] + xWe + rf[i] * xWfuel

            xcg[i] = xW / W
      end

      #      rpayF = rpay[1]
      #      rpayB = rpay[2]
      #
      #      xcgF = xcg[1]
      #      xcgB = xcg[2]

      return rf[1], rf[2], rpay[1], rpay[2], xcg[1], xcg[2]
end # cglpay

function cabin_centroid(nftanks,fuse,xftankaft,lftank)
      # Calculate x location of cabin centroid  and length of cabin
      if nftanks == 1
            if xftankaft == 0.0 #If tank is at the front
                  xcabin = 0.5 * (fuse.layout.x_start_cylinder + lftank + 2.0*ft_to_m + fuse.layout.x_pressure_shell_aft)
                  lcabin = fuse.layout.x_pressure_shell_aft - fuse.layout.x_end_cylinder + fuse.layout.l_cabin_cylinder #cabin length is smaller if there are fuel tanks
            else #tank is at rear
                  xcabin = 0.5 * (fuse.layout.x_pressure_shell_fwd + fuse.layout.x_end_cylinder - (lftank + 2.0*ft_to_m))
                  lcabin = fuse.layout.x_start_cylinder - fuse.layout.x_pressure_shell_fwd + fuse.layout.l_cabin_cylinder #cabin length is smaller if there are fuel tanks
            end
      elseif nftanks == 2
            xcabin = 0.5 * (fuse.layout.x_pressure_shell_fwd + fuse.layout.x_pressure_shell_aft) #TODO noticed convergence issues if the average of the blends is used instead
            lcabin = fuse.layout.l_cabin_cylinder
      elseif nftanks == 0
            xcabin = 0.5 * (fuse.layout.x_pressure_shell_fwd + fuse.layout.x_pressure_shell_aft)
            lcabin = fuse.layout.x_pressure_shell_aft - fuse.layout.x_pressure_shell_fwd
      end
      return xcabin,lcabin
end