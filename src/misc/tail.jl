using DocStringExtensions

"""
$TYPEDEF

Tail

$TYPEDFIELDS
"""
@kwdef mutable struct Tail
    """Tail Layout """
    layout::WingLayout = WingLayout()
    """Tail Section """
    outboard::WingSection= WingSection()
    inboard::WingSection = WingSection()
    """Tail Strut"""
    has_strut::Bool = false
    strut::Strut = Strut()
    """Tip lift roll-off factor"""
    tip_lift_loss::Float64 = 0.0
    """Aircraft pitching moment contribution from the weight distribution of the strut [N m]"""
    dxW::Float64 = 0
    # igbs = igbo
    # strutz = 0
    # lambdat = gammat = iglambdah 
    # lambdas = gammas = 1.0

    # create inner
    # lambdas, gammas = 1.0
    # igbs = igbo
    # hboxs = hboxh
    """Tail Weight [N] """
    weight::Float64 = 0
    """Tail Added Weight Fraction"""
    weight_fraction_added::Float64 = 0
    """Tail Max CL """
    CL_max::Float64 = 0
    """Tail Volume [m^3] """
    volume::Float64 = 0
    """Tail Sizing factor: 1=set Sh via specified Vh, 2=et Sh via CLhCGfwd at max-forward CG during landing """
    size::Int64 = 0
    """Tail Downwash factor dε/dα """
    downwash_factor::Float64 = 0
    """Tail max fwd CG (only used if HTsize == "maxforwardCG") """
    CL_max_fwd_CG::Float64 = 0
    """Tail Minimum static margin"""
    SM_min::Float64 = 0
    """Max Tail down load. Tail download param at max load case"""
    CL_CLmax::Float64 = 0
    """Number of Tails"""
    ntails::Float64 = 0
    """Move wingbox factor. 0="fix" wing position ,1=move wing to get CLh="CLhspec" in cruise, 2= move wing to get min static margin = "SMmin"  """
    move_wingbox::Int64 = 0
    
end

function wing_additional_weight(tail::Tail)
    return tail.weight_fraction_added
end

"""
"""
function Base.getproperty(obj::Tail, sym::Symbol)
    if hasfield(Tail, sym)
        return getfield(obj, sym)
    elseif hasfield(WingLayout, sym)
        return getfield(obj.layout, sym)
    else
        throw(KeyError("Property $sym not found in Wing or WingLayout"))
    end
end  # function Base.getproperty
