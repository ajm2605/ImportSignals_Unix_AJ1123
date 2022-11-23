function [varsToDelete] = whoToKeep(whoIn, keepMe)
    boolKeep = false(length(whoIn),1);
    for i = 1:length(keepMe)
        boolKeep = boolKeep|cellfun(@(x) contains(keepMe{i}, x), whoIn);
    end
    varsToDelete = whoIn(~boolKeep);
end

