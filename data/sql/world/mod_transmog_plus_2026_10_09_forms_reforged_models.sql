-- The realm's base client (Project Reforged HD) uses CreatureModelData 9511 and 9571 itself, so the
-- druid form patch (now patch-R.MPQ) moves those two form models to 9590 and 9591. Same rows, new IDs.
-- Repeats the change in mod_transmog_plus_2026_10_08_forms_data.sql for servers that applied it before.
DELETE FROM `creaturemodeldata_dbc` WHERE `ID` IN (9511, 9571, 9590, 9591);
INSERT INTO `creaturemodeldata_dbc` (`ID`, `Flags`, `ModelName`, `SizeClass`, `ModelScale`, `BloodID`, `FootprintTextureID`, `FootprintTextureLength`, `FootprintTextureWidth`, `FootprintParticleScale`, `FoleyMaterialID`, `FootstepShakeSize`, `DeathThudShakeSize`, `SoundID`, `CollisionWidth`, `CollisionHeight`, `MountHeight`, `GeoBoxMinX`, `GeoBoxMinY`, `GeoBoxMinZ`, `GeoBoxMaxX`, `GeoBoxMaxY`, `GeoBoxMaxZ`, `WorldEffectScale`, `AttachedEffectScale`, `MissileCollisionRadius`, `MissileCollisionPush`, `MissileCollisionRaise`) VALUES
(9590, 0, 'Creature\\RetailForms\\Stormcrowdruid\\Stormcrowdruid.mdx', 1, 1, 3, 5, 18, 12, 1, 0, 0, 0, 390, 0.611111, 2.03128, 0, -1.7049, -3.40195, 0.470899, 2.25242, 3.43544, 4.8435, 1, 1, 0, 0, 0),
(9591, 16, 'Creature\\RetailForms\\Druidbear2Artifact6\\Druidbear2Artifact6.mdx', 1, 1, 1, 7, 18, 12, 1, 0, 0, 0, 3022, 0.611111, 2.03128, 0, -2.30731, -2.73374, -0.175778, 3.1049, 2.54621, 4.89254, 1, 1, 0, 0, 0);
UPDATE `creaturedisplayinfo_dbc` SET `ModelID` = 9590 WHERE `ID` IN (95027, 95028);
UPDATE `creaturedisplayinfo_dbc` SET `ModelID` = 9591 WHERE `ID` IN (95196, 95197, 95198, 95199);
