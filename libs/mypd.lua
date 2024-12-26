function pd.Class:SvgObjOutlet(outlet, outletId, atoms)
	local str = "<" .. outletId .. ">"
	pd[str] = atoms
	pd._outlet(self._object, outlet, "SvgObj", { str })
end
