-- Fictional original world. IDs and names do not depend on menus, RNG calls or seasons.
local Config={
 START_COUNTRY='asteria', START_CLUB='asteria_081', CLUBS_PER_DIVISION=16,
 DIRECT_PROMOTION=2, RELEGATION=2, HISTORY_LIMIT=40,
 -- Two direct places in each direction, mirrored at each internal boundary.
 QUALIFICATION={championsLeaguePlaces=2,challengeLeaguePlaces=1,challengeCupPlaces=1},
 COUNTRIES={
  {id='asteria',name='Asteria',divisions=6,culture='development',base=84,color={87,157,219},cities={'Larkhaven','Brindle','Eastmere','Ashbrook','Stoneford','Willowbay','Dunvale','Rookhill','Northgate','Cedarwick','Fairwater','Westhaven','Brookstead','Ironmere','Oakridge','Highfield'}},
  {id='brumora',name='Brumora',divisions=2,culture='pressing',base=81,color={164,93,183},cities={'Frostholm','Hearthwick','Grayhaven','Mossford','Alderfell','Cloudmere','Redwick','Winterbay','Longvale','Blackthorn','Duskfield','Hollowford','Rivermoor','Sablehill','Flintgate','Ravenbrook'}},
  {id='solara',name='Solara',divisions=2,culture='possession',base=83,color={240,176,65},cities={'Aurivale','Luminara','Coraluz','Sereno','Bellora','Riodoro','Solviento','Terramar','Arcoluz','Monteluna','Valdela','Clarossa','Olivara','Lucevia','Fiorenza','Estrella'}},
  {id='valdora',name='Valdora',divisions=2,culture='compact',base=80,color={198,82,85},cities={'Valtora','Pietrano','Castelle','Fontara','Verdano','Cortella','Ravello','Ponterra','Ardenza','Lavenza','Portello','Neravalle','Caldero','Miravento','Stradella','Vincera'}},
  {id='maravia',name='Maravia',divisions=2,culture='wings',base=79,color={47,177,165},cities={'Portavela','Marisol','Oceara','Velamar','Caisara','Brisola','Naveira','Rochamar','Santela','Miragua','Salvera','Costela','Varimar','Lumamar','Coraleira','Praiora'}},
  {id='nordvik',name='Nordvik',divisions=2,culture='physical',base=78,color={93,169,205},cities={'Skeldal','Vinterby','Havnesund','Nordfell','Eikholm','Bergstrand','Lindvik','Torsdal','Falksund','Skarheim','Solberg','Isenfjord','Ostervik','Brannby','Hjellstad','Varglund'}},
  {id='karuna',name='Karuna',divisions=2,culture='counter',base=80,color={222,119,69},cities={'Kairava','Suryan','Velapur','Namaru','Talima','Aranya','Devora','Mahana','Nivara','Samira','Paruna','Indara','Rohava','Akasha','Tavira','Lakana'}},
  {id='vestria',name='Vestria',divisions=2,culture='technical',base=82,color={94,179,119},cities={'Vesgrad','Zelenko','Novara','Dravice','Lunovec','Borava','Kralova','Vetrina','Mostara','Ruzdov','Danova','Ostara','Slavena','Belvica','Morava','Dubrina'}},
 },
 -- Sporting dates, not elapsed real-world days. All competition slots are disjoint.
 DATES={friendly=1,supercup=2,national96={10,26,42,58,74,90,110},national32={42,58,74,90,110},international={18,46,78,114}},
 WINDOWS={{first=0,last=36},{first=70,last=92}},
}
return Config
