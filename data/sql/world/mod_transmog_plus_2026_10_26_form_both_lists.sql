-- A look can be in more than one form's list: an otter for both Travel and Aquatic Form. Picked
-- for both, the two forms swap for free on entering and leaving water (Transmog.Forms.WaterSwap).
ALTER TABLE `mod_transmog_plus_forms` DROP PRIMARY KEY, ADD PRIMARY KEY (`DisplayId`, `Form`);
