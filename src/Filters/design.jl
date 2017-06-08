# Filter prototypes, transformations, and transforms

using ..Windows

abstract type FilterType end

#
# Butterworth prototype
#

function Butterworth(T::Type, n::Integer)
    n > 0 || error("n must be positive")

    poles = zeros(Complex{T}, n)
    for i = 1:div(n, 2)
        w = convert(T, 2i-1)/2n
        pole = complex(-sinpi(w), cospi(w))
        poles[2i-1] = pole
        poles[2i] = conj(pole)
    end
    if isodd(n)
        poles[end] = -1
    end
    ZeroPoleGain(T[], poles, 1)
end
Butterworth(n::Integer) = Butterworth(Float64, n)

#
# Chebyshev type I and II prototypes
#

function chebyshev_poles(T::Type, n::Integer, ε::Real)
    p = zeros(Complex{T}, n)
    μ = asinh(convert(T, 1)/ε)/n
    b = -sinh(μ)
    c = cosh(μ)
    for i = 1:div(n, 2)
        w = convert(T, 2i-1)/2n
        pole = complex(b*sinpi(w), c*cospi(w))
        p[2i-1] = pole
        p[2i] = conj(pole)
    end
    if isodd(n)
        w = convert(T, 2*div(n, 2)+1)/2n
        pole = b*sinpi(w)
        p[end] = pole
    end
    p
end

function Chebyshev1(T::Type, n::Integer, ripple::Real)
    n > 0 || error("n must be positive")
    ripple >= 0 || error("ripple must be non-negative")

    ε = sqrt(10^(convert(T, ripple)/10)-1)
    p = chebyshev_poles(T, n, ε)
    k = one(T)
    for i = 1:div(n, 2)
        k *= abs2(p[2i])
    end
    if iseven(n)
        k /= sqrt(1+abs2(ε))
    else
        k *= real(-p[end])
    end
    ZeroPoleGain(Float64[], p, k)
end
Chebyshev1(n::Integer, ripple::Real) = Chebyshev1(Float64, n, ripple)

function Chebyshev2(T::Type, n::Integer, ripple::Real)
    n > 0 || error("n must be positive")
    ripple >= 0 || error("ripple must be non-negative")

    ε = 1/sqrt(10^(convert(T, ripple)/10)-1)
    p = chebyshev_poles(T, n, ε)
    for i = 1:length(p)
        p[i] = inv(p[i])
    end

    z = zeros(Complex{T}, n-isodd(n))
    k = one(T)
    for i = 1:div(n, 2)
        w = convert(T, 2i-1)/2n
        ze = Complex(zero(T), -inv(cospi(w)))
        z[2i-1] = ze
        z[2i] = conj(ze)
        k *= abs2(p[2i])/abs2(ze)
    end
    isodd(n) && (k *= -real(p[end]))

    ZeroPoleGain(z, p, k)
end
Chebyshev2(n::Integer, ripple::Real) = Chebyshev2(Float64, n, ripple)

#
# Elliptic prototype
#
# See Orfanidis, S. J. (2007). Lecture notes on elliptic filter design.
# Retrieved from http://www.ece.rutgers.edu/~orfanidi/ece521/notes.pdf

# Compute Landen sequence for evaluation of elliptic functions
function landen(k::Real)
    niter = 7
    kn = Array{typeof(k)}(niter)
    # Eq. (50)
    for i = 1:niter
        kn[i] = k = abs2(k/(1+sqrt(1-abs2(k))))
    end
    kn
end

# cde computes cd(u*K(k), k)
# sne computes sn(u*K(k), k)
# Both accept the Landen sequence as generated by landen above
for (fn, init) in ((:cde, :(cospi(u/2))), (:sne, :(sinpi(u/2))))
    @eval begin
        function $fn(u::Number, landen::Vector{T}) where T<:Real
            winv = inv($init)
            # Eq. (55)
            for i = length(landen):-1:1
                oldwinv = winv
                winv = 1/(1+landen[i])*(winv+landen[i]/winv)
            end
            w = inv(winv)
        end
    end
end

# sne inverse
function asne(w::Number, k::Real)
    oldw = NaN
    while w != oldw
        oldw = w
        kold = k
        # Eq. (50)
        k = abs2(k/(1+sqrt(1-abs2(k))))
        # Eq. (56)
        w = 2*w/((1+k)*(1+sqrt(1-abs2(kold)*w^2)))
    end
    2*asin(w)/π
end

function Elliptic(T::Type, n::Integer, rp::Real, rs::Real)
    n > 0 || error("n must be positive")
    rp > 0 || error("rp must be positive")
    rp < rs || error("rp must be less than rs")

    # Eq. (2)
    εp = sqrt(10^(convert(T, rp)/10)-1)
    εs = sqrt(10^(convert(T, rs)/10)-1)

    # Eq. (3)
    k1 = εp/εs
    k1 >= 1 && error("filter order is too high for parameters")

    # Eq. (20)
    k1′² = 1 - abs2(k1)
    k1′ = sqrt(k1′²)
    k1′_landen = landen(k1′)

    # Eq. (47)
    k′ = one(T)
    for i = 1:div(n, 2)
        k′ *= sne(convert(T, 2i-1)/n, k1′_landen)
    end
    k′ = k1′²^(convert(T, n)/2)*k′^4

    k = sqrt(1 - abs2(k′))
    k_landen = landen(k)

    # Eq. (65)
    v0 = -im/n*asne(im/εp, k1)

    z = Array{Complex{T}}(2*div(n, 2))
    p = Array{Complex{T}}(n)
    gain = one(T)
    for i = 1:div(n, 2)
        # Eq. (43)
        w = convert(T, 2i-1)/n

        # Eq. (62)
        ze = complex(zero(T), -inv(k*cde(w, k_landen)))
        z[2i-1] = ze
        z[2i] = conj(ze)

        # Eq. (64)
        pole = im*cde(w - im*v0, k_landen)
        p[2i] = pole
        p[2i-1] = conj(pole)

        gain *= abs2(pole)/abs2(ze)
    end

    if isodd(n)
        pole = im*sne(im*v0, k_landen)
        p[end] = pole
        gain *= abs(pole)
    else
        gain *= 10^(-convert(T, rp)/20)
    end

    ZeroPoleGain(z, p, gain)
end
Elliptic(n::Integer, rp::Real, rs::Real) = Elliptic(Float64, n, rp, rs)

#
# Prototype transformation types
#

function normalize_freq(w::Real, fs::Real)
    w <= 0 && error("frequencies must be positive")
    f = 2*w/fs
    f >= 1 && error("frequencies must be less than the Nyquist frequency $(fs/2)")
    f
end

struct Lowpass{T} <: FilterType
    w::T
end
Lowpass(w::Real; fs::Real=2) = Lowpass{typeof(w/1)}(normalize_freq(w, fs))

struct Highpass{T} <: FilterType
    w::T
end
Highpass(w::Real; fs::Real=2) = Highpass{typeof(w/1)}(normalize_freq(w, fs))

struct Bandpass{T} <: FilterType
    w1::T
    w2::T
end
function Bandpass(w1::Real, w2::Real; fs::Real=2)
    w1 < w2 || error("w1 must be less than w2")
    Bandpass{Base.promote_typeof(w1/1, w2/1)}(normalize_freq(w1, fs), normalize_freq(w2, fs))
end

struct Bandstop{T} <: FilterType
    w1::T
    w2::T
end
function Bandstop(w1::Real, w2::Real; fs::Real=2)
    w1 < w2 || error("w1 must be less than w2")
    Bandstop{Base.promote_typeof(w1/1, w2/1)}(normalize_freq(w1, fs), normalize_freq(w2, fs))
end

#
# Prototype transformation implementations
#
# The formulas implemented here come from the documentation for the
# corresponding functionality in Octave, available at
# https://staff.ti.bfh.ch/sha1/Octave/index/f/sftrans.html
# The Octave implementation was not consulted in creating this code.

# Create a lowpass filter from a lowpass filter prototype
transform_prototype(ftype::Lowpass, proto::ZeroPoleGain) =
    ZeroPoleGain(ftype.w * proto.z, ftype.w * proto.p,
              proto.k * ftype.w^(length(proto.p)-length(proto.z)))

# Create a highpass filter from a lowpass filter prototype
function transform_prototype(ftype::Highpass, proto::ZeroPoleGain)
    z = proto.z
    p = proto.p
    nz = length(z)
    np = length(p)
    newz = zeros(Base.promote_eltype(z, p), max(nz, np))
    newp = zeros(Base.promote_eltype(z, p), max(nz, np))
    num = one(eltype(z))
    for i = 1:nz
        num *= -z[i]
        newz[i] = ftype.w / z[i]
    end
    den = one(eltype(p))
    for i = 1:np
        den *= -p[i]
        newp[i] = ftype.w / p[i]
    end

    abs(real(num) - 1) < np*eps(real(num)) && (num = 1)
    abs(real(den) - 1) < np*eps(real(den)) && (den = 1)
    ZeroPoleGain(newz, newp, proto.k * real(num)/real(den))
end

# Create a bandpass filter from a lowpass filter prototype
function transform_prototype(ftype::Bandpass, proto::ZeroPoleGain)
    z = proto.z
    p = proto.p
    nz = length(z)
    np = length(p)
    ncommon = min(nz, np)
    newz = zeros(Base.promote_eltype(z, p), 2*nz+np-ncommon)
    newp = zeros(Base.promote_eltype(z, p), 2*np+nz-ncommon)
    for (oldc, newc) in ((p, newp), (z, newz))
        for i = 1:length(oldc)
            b = oldc[i] * ((ftype.w2 - ftype.w1)/2)
            pm = sqrt(b^2 - ftype.w2 * ftype.w1)
            newc[2i-1] = b + pm
            newc[2i] = b - pm
        end
    end
    ZeroPoleGain(newz, newp, proto.k * (ftype.w2 - ftype.w1) ^ (np - nz))
end

# Create a bandstop filter from a lowpass filter prototype
function transform_prototype(ftype::Bandstop, proto::ZeroPoleGain)
    z = proto.z
    p = proto.p
    nz = length(z)
    np = length(p)
    npairs = nz+np-min(nz, np)
    newz = Array{Base.promote_eltype(z, p)}(2*npairs)
    newp = Array{Base.promote_eltype(z, p)}(2*npairs)

    num = one(eltype(z))
    for i = 1:nz
        num *= -z[i]
        b = (ftype.w2 - ftype.w1)/2/z[i]
        pm = sqrt(b^2 - ftype.w2 * ftype.w1)
        newz[2i-1] = b - pm
        newz[2i] = b + pm
    end

    den = one(eltype(p))
    for i = 1:np
        den *= -p[i]
        b = (ftype.w2 - ftype.w1)/2/p[i]
        pm = sqrt(b^2 - ftype.w2 * ftype.w1)
        newp[2i-1] = b - pm
        newp[2i] = b + pm
    end

    # Any emaining poles/zeros are real and not cancelled
    npm = sqrt(-complex(ftype.w2 * ftype.w1))
    for (n, newc) in ((np, newp), (nz, newz))
        for i = n+1:npairs
            newc[2i-1] = -npm
            newc[2i] = npm
        end
    end

    abs(real(num) - 1) < np*eps(real(num)) && (num = 1)
    abs(real(den) - 1) < np*eps(real(den)) && (den = 1)
    ZeroPoleGain(newz, newp, proto.k * real(num)/real(den))
end

transform_prototype(ftype, proto::FilterCoefficients) =
    transform_prototype(ftype, convert(ZeroPoleGain, proto))

analogfilter(ftype::FilterType, proto::FilterCoefficients) =
    transform_prototype(ftype, proto)

# Bilinear transform
bilinear(f::FilterCoefficients, fs::Real) = bilinear(convert(ZeroPoleGain, f), fs)
function bilinear(f::ZeroPoleGain{Z,P,K}, fs::Real) where {Z,P,K}
    ztype = typeof(0 + zero(Z)/fs)
    z = fill(convert(ztype, -1), max(length(f.p), length(f.z)))

    ptype = typeof(0 + zero(P)/fs)
    p = Array{typeof(zero(P)/fs)}(length(f.p))

    num = one(one(fs) - one(Z))
    for i = 1:length(f.z)
        z[i] = (2 + f.z[i] / fs)/(2 - f.z[i] / fs)
        num *= (2 * fs - f.z[i])
    end

    den = one(one(fs) - one(P))
    for i = 1:length(f.p)
        p[i] = (2 + f.p[i] / fs)/(2 - f.p[i]/fs)
        den *= (2 * fs - f.p[i])
    end

    ZeroPoleGain(z, p, f.k * real(num)/real(den))
end

# Pre-warp filter frequencies for digital filtering
prewarp(ftype::Union{Lowpass, Highpass}) = (typeof(ftype))(4*tan(pi*ftype.w/2))
prewarp(ftype::Union{Bandpass, Bandstop}) = (typeof(ftype))(4*tan(pi*ftype.w1/2), 4*tan(pi*ftype.w2/2))

# Digital filter design
digitalfilter(ftype::FilterType, proto::FilterCoefficients) =
    bilinear(transform_prototype(prewarp(ftype), proto), 2)

#
# Special filter types
#

# See Orfanidis, S. J. (1996). Introduction to signal processing.
# Englewood Cliffs, N.J: Prentice Hall, p. 370
function iirnotch(w::Real, bandwidth::Real; fs=2)
    w = normalize_freq(w, fs)
    bandwidth = normalize_freq(bandwidth, fs)

    # Eq. 8.2.23
    b = 1/(1+tan(pi*bandwidth/2))
    # Eq. 8.2.22
    cosw0 = cospi(w)
    Biquad(b, -2b*cosw0, b, -2b*cosw0, 2b-1)
end

#
# FIR filter design
#

# Get length and alpha for Kaiser window filter with specified
# transition band width and stopband attenuation in dB
function kaiserord(transitionwidth::Real, attenuation::Real=60)
    n = ceil(Int, (attenuation - 7.95)/(π*2.285*transitionwidth))+1

    if attenuation > 50
        β = 0.1102*(attenuation - 8.7)
    elseif attenuation >= 21
        β = 0.5842*(attenuation - 21)^0.4 + 0.07886*(attenuation - 21)
    else
        β = 0.0
    end

    return n, β/π
end

struct FIRWindow{T}
    window::Vector{T}
    scale::Bool
end
FIRWindow(window::Vector; scale::Bool=true) = FIRWindow(window, scale)

# FIRWindow(n::Integer, window::Function, args...) = FIRWindow(window(n, args...))
FIRWindow(; transitionwidth::Real=throw(ArgumentError("must specify transitionwidth")),
          attenuation::Real=60, scale::Bool=true) =
    FIRWindow(kaiser(kaiserord(transitionwidth, attenuation)...), scale)

# Compute coefficients for FIR prototype with specified order
function firprototype(n::Integer, ftype::Lowpass)
    w = ftype.w

    [w*sinc(w*(k-(n-1)/2)) for k = 0:(n-1)]
end

function firprototype(n::Integer, ftype::Bandpass)
    w1 = ftype.w1
    w2 = ftype.w2

    [w2*sinc(w2*(k-(n-1)/2)) - w1*sinc(w1*(k-(n-1)/2)) for k = 0:(n-1)]
end

function firprototype(n::Integer, ftype::Highpass)
    w = ftype.w
    isodd(n) || throw(ArgumentError("FIRWindow highpass filters must have an odd number of coefficients"))

    out = [-w*sinc(w*(k-(n-1)/2)) for k = 0:(n-1)]
    out[div(n, 2)+1] += 1
    out
end

function firprototype(n::Integer, ftype::Bandstop)
    w1 = ftype.w1
    w2 = ftype.w2
    isodd(n) || throw(ArgumentError("FIRWindow bandstop filters must have an odd number of coefficients"))

    out = [w1*sinc(w1*(k-(n-1)/2)) - w2*sinc(w2*(k-(n-1)/2)) for k = 0:(n-1)]
    out[div(n, 2)+1] += 1
    out
end

scalefactor(coefs::Vector, ::Union{Lowpass, Bandstop}) = sum(coefs)
function scalefactor(coefs::Vector, ::Highpass)
    c = zero(coefs[1])
    for k = 1:length(coefs)
        c += ifelse(isodd(k), coefs[k], -coefs[k])
    end
    c
end
function scalefactor(coefs::Vector, ftype::Bandpass)
    n = length(coefs)
    freq = middle(ftype.w1, ftype.w2)
    c = zero(coefs[1])
    for k = 0:n-1
        c += coefs[k+1]*cospi(freq*(k-(n-1)/2))
    end
    c
end

function digitalfilter(ftype::FilterType, proto::FIRWindow)
    coefs = firprototype(length(proto.window), ftype)
    @assert length(proto.window) == length(coefs)
    out = coefs .* proto.window
    proto.scale ? scale!(out, 1/scalefactor(out, ftype)) : out
end


# Compute FIR coefficients necessary for arbitrary rate resampling
function resample_filter(rate::AbstractFloat, Nϕ = 32, rel_bw = 1.0, attenuation = 60)
    f_nyq       = rate >= 1.0 ? 1.0/Nϕ : rate/Nϕ
    cutoff      = f_nyq * rel_bw
    trans_width = cutoff * 0.2

    # Determine resampling filter order
    hLen, α = kaiserord(trans_width, attenuation)

    # Round the number of taps up to a multiple of Nϕ.
    # Otherwise the missing taps will be filled with 0.
    hLen = Nϕ * ceil(Int, hLen/Nϕ)

    # Ensure that the filter is an odd length
    if (iseven(hLen))
        hLen += 1
    end

    # Design filter
    h = digitalfilter(Lowpass(cutoff), FIRWindow(kaiser(hLen, α)))
    scale!(h, Nϕ)
end

# Compute FIR coefficients necessary for rational rate resampling
function resample_filter(rate::Rational, rel_bw = 1.0, attenuation = 60)
    Nϕ          = numerator(rate)
    decimation  = denominator(rate)
    f_nyq       = min(1/Nϕ, 1/decimation)
    cutoff      = f_nyq * rel_bw
    trans_width = cutoff * 0.2

    # Determine resampling filter order
    hLen, α = kaiserord(trans_width, attenuation)

    # Round the number of taps up to a multiple of Nϕ (same as interpolation factor).
    # Otherwise the missing taps will be filled with 0.
    hLen = Nϕ * ceil(Int, hLen/Nϕ)

    # Ensure that the filter is an odd length
    if (iseven(hLen))
        hLen += 1
    end

    # Design filter
    h = digitalfilter(Lowpass(cutoff), FIRWindow(kaiser(hLen, α)))
    scale!(h, Nϕ)
end
