function canAccessNaribwe()
    if Tracker:ProviderCountForCode("lemurian_ship") > 0 then
        return 1
    end

    if Tracker:ProviderCountForCode("briggs_battle") > 0 then
        return Tracker:ProviderCountForCode("frost_jewel") + Tracker:ProviderCountForCode("scoop_gem")
    end

    return 0
end

function canAccessKibombo()
    if canAccessNaribwe() == 0 then
        return 0
    else
        if Tracker:ProviderCountForCode("lemurian_ship") > 0 then
            return 1
        end

        return Tracker:ProviderCountForCode("frost_jewel") + Tracker:ProviderCountForCode("whirlwind")
    end
end

function canAccessShip()
    if Tracker:ProviderCountForCode("lemurian_ship") > 0 then
        return Tracker:ProviderCountForCode("grindstone") + Tracker:ProviderCountForCode("trident")
    else
        if Tracker:ProviderCountForCode("gabomba_statue") > 0 then
            return Tracker:ProviderCountForCode("black_crystal")
        else
			return 0
		end
    end
end

function canAccessUpperMars()
    if Tracker:ProviderCountForCode("burst_brooch") > 0 and Tracker:ProviderCountForCode("blaze") > 0 and Tracker:ProviderCountForCode("reveal") > 0 and Tracker:ProviderCountForCode("teleport_lapis") > 0 and Tracker:ProviderCountForCode("pound_cube") > 0 then
        return Tracker:ProviderCountForCode("mars_star")
    end
	return 0
end