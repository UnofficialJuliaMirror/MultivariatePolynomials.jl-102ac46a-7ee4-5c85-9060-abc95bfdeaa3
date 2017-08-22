# We reverse the order of comparisons here so that the result
# of x < y is equal to the result of Monomial(x) < Monomial(y)
@pure isless(v1::AbstractVariable, v2::AbstractVariable) = name(v1) > name(v2)
isless(m1::AbstractTermLike, m2::AbstractTermLike) = isless(promote(m1, m2)...)

function isless(t1::AbstractTerm, t2::AbstractTerm)
    if monomial(t1) < monomial(t2)
        true
    elseif monomial(t1) == monomial(t2)
        coefficient(t1) < coefficient(t2)
    else
        false
    end
end

# promoting multiplication is not a good idea
# For example a polynomial of Float64 * a polynomial of JuMP affine expression
# is a polynomial of JuMP affine expression but if we promote it would be a
# polynomial of quadratic expression
for op in [:+, :-, :(==)]
    @eval $op(p1::APL, p2::APL) = $op(promote(p1, p2)...)
end
isapprox(p1::APL, p2::APL; kwargs...) = isapprox(promote(p1, p2)...; kwargs...)

# @eval $op(p::APL, α) = $op(promote(p, α)...) would be less efficient
for (op, fun) in [(:+, :plusconstant), (:-, :minusconstant), (:*, :multconstant), (:(==), :eqconstant)]
    @eval $op(p::APL, α) = $fun(p, α)
    @eval $op(α, p::APL) = $fun(α, p)
end
isapprox(p::APL, α; kwargs...) = isapprox(promote(p, α)...; kwargs...)
isapprox(α, p::APL; kwargs...) = isapprox(promote(p, α)...; kwargs...)

(-)(m::AbstractMonomialLike) = (-1) * m
(-)(t::AbstractTermLike) = (-coefficient(t)) * monomial(t)
(-)(p::APL) = polynomial((-).(terms(p)))
(+)(p::Union{APL, RationalPoly}) = p

# Avoid adding a zero constant that might artificially increase the Newton polytope
# Need to add polynomial conversion for type stability
plusconstant(p::APL, α) = iszero(α) ? polynomial(p) : p + constantterm(α, p)
plusconstant(α, p::APL) = plusconstant(p, α)
minusconstant(p::APL, α) = iszero(α) ? polynomial(p) : p - constantterm(α, p)
minusconstant(α, p::APL) = iszero(α) ? polynomial(-p) : constantterm(α, p) - p

# Coefficients and variables commute
multconstant(α, v::AbstractVariable) = multconstant(α, monomial(v)) # TODO linear term
multconstant(m::AbstractMonomialLike, α) = multconstant(α, m)
multconstant(α, p::AbstractPolynomialLike) = multconstant(α, polynomial(p))
multconstant(p::AbstractPolynomialLike, α) = multconstant(polynomial(p), α)

multconstant(α, t::AbstractTermLike)    = (α*coefficient(t)) * monomial(t)
multconstant(t::AbstractTermLike, α)    = (coefficient(t)*α) * monomial(t)

(*)(m1::AbstractMonomialLike, m2::AbstractMonomialLike) = mapexponents(+, m1, m2)
#(*)(m1::AbstractMonomialLike, m2::AbstractMonomialLike) = *(monomial(m1), monomial(m2))

(*)(m::AbstractMonomialLike, t::AbstractTermLike) = coefficient(t) * (m * monomial(t))
(*)(t::AbstractTermLike, m::AbstractMonomialLike) = coefficient(t) * (monomial(t) * m)
(*)(t1::AbstractTermLike, t2::AbstractTermLike) = (coefficient(t1) * coefficient(t2)) * (monomial(t1) * monomial(t2))

(*)(t::AbstractTermLike, p::APL) = polynomial(map(te -> t * te, terms(p)))
(*)(p::APL, t::AbstractTermLike) = polynomial(map(te -> te * t, terms(p)))
(*)(p::APL, q::APL) = polynomial(p) * polynomial(q)

# guaranteed that monomial(t1) > monomial(t2)
function _polynomial_2terms(t1::TT, t2::TT, ::Type{T}) where {TT<:AbstractTerm, T}
    if iszero(t1)
        polynomial(t2, T)
    elseif iszero(t2)
        polynomial(t1, T)
    else
        polynomial(termtype(TT, T)[t1, t2], SortedUniqState())
    end
end
for op in [:+, :-]
    @eval begin
        $op(t1::AbstractTermLike, t2::AbstractTermLike) = $op(term(t1), term(t2))
        $op(t1::AbstractTerm, t2::AbstractTerm) = $op(promote(t1, t2)...)
        function $op(t1::TT, t2::TT) where {T, TT <: AbstractTerm{T}}
            S = Base.promote_op($op, T, T)
            # t1 > t2 would compare the coefficient in case the monomials are equal
            # and it will throw a MethodError in case the coefficients are not comparable
            if monomial(t1) == monomial(t2)
                polynomial($op(coefficient(t1), coefficient(t2)) * monomial(t1), S)
            elseif monomial(t1) > monomial(t2)
                ts = _polynomial_2terms(t1, $op(t2), S)
            else
                ts = _polynomial_2terms($op(t2), t1, S)
            end
        end
    end
end

Base.transpose(v::AbstractVariable) = v
Base.transpose(m::AbstractMonomial) = m
Base.transpose(t::T) where {T <: AbstractTerm} = transpose(coefficient(t)) * monomial(t)
Base.transpose(p::AbstractPolynomialLike) = polynomial(map(transpose, terms(p)))

Base.dot(p1::AbstractPolynomialLike, p2::AbstractPolynomialLike) = p1' * p2
Base.dot(x, p::AbstractPolynomialLike) = x' * p
Base.dot(p::AbstractPolynomialLike, x) = p' * x

# Amazingly, this works! Thanks, StaticArrays.jl!
"""
Convert a tuple of variables into a static vector to allow array-like usage.
The element type of the vector will be Monomial{vars, length(vars)}.
"""
Base.vec(vars::Tuple{Vararg{AbstractVariable}}) = [vars...]
# vec(vars::Tuple{Vararg{<:TypedVariable}}) = SVector(vars)