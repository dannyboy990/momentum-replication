*==============================================================================
* _polish_cells.do  -  helper for polished siunitx d-column LaTeX tables
*
* Defines program  pcell <varname>  which, for the CURRENTLY ACTIVE estimates
* (e.g. after `estimates restore <name>` or right after a reghdfe), returns:
*     r(b)  = coefficient formatted to 3 dp with \sym{*}/\sym{**}/\sym{***}
*     r(t)  = t-statistic as text-mode siunitx cell  {(x.xx)}
*     r(star) = the bare star macro (\sym{**} etc.)
* Stars use 2*ttail(e(df_r),|t|), matching esttab's default for reghdfe.
*==============================================================================
cap program drop pcell
program define pcell, rclass
    args var
    local b  = _b[`var']
    local se = _se[`var']
    local t  = `b'/`se'
    local df = e(df_r)
    local p  = 2*ttail(`df', abs(`t'))
    local s ""
    if `p' < 0.10 local s "\sym{*}"
    if `p' < 0.05 local s "\sym{**}"
    if `p' < 0.01 local s "\sym{***}"
    return local b    = strtrim(string(`b',"%14.3f")) + "`s'"
    return local t    = "{(" + strtrim(string(`t',"%14.2f")) + ")}"
    return local star = "`s'"
end

* commaN : format e(N) (or any integer scalar) as 53{,}324{,}145 for d-columns
cap program drop commaN
program define commaN, rclass
    args n
    local out = string(`n',"%15.0fc")
    local out : subinstr local out "," "{,}", all
    return local n = strtrim("`out'")
end
