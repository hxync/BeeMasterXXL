return function ( func, errMessage, errFunc )
    local result = func()
	if not result and errMessage then
		print( errMessage )
	end
    while not result do
        if errFunc then
            errFunc()
        end
        os.sleep(1)
        result = func()
    end
    return result
end