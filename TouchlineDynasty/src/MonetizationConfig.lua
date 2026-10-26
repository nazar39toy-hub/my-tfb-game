-- Owner configuration. 0 is deliberately DISABLED, never a mock live ID.
-- Prices are fetched by the client using GetProductInfoAsync (personalized).
local K={}
K.passes={
 {id='identity',robloxId=0,nameKey='shop.identity',descriptionKey='shop.identity_desc',items={'hoops','crest_star'}},
 {id='stadium',robloxId=0,nameKey='shop.stadium',descriptionKey='shop.stadium_desc',items={'designer'}},
 {id='broadcast',robloxId=0,nameKey='shop.broadcast',descriptionKey='shop.broadcast_desc',items={'broadcast_pro'}},
 {id='supporter',robloxId=0,nameKey='shop.supporter',descriptionKey='shop.supporter_desc',items={'supporter_badge'}},
}
K.products={
 {id='tokens_s',robloxId=0,nameKey='shop.tokens_s',descriptionKey='shop.tokens_only',tokens=100},
 {id='tokens_m',robloxId=0,nameKey='shop.tokens_m',descriptionKey='shop.tokens_only',tokens=300},
 {id='tokens_l',robloxId=0,nameKey='shop.tokens_l',descriptionKey='shop.tokens_only',tokens=800},
 {id='donation_s',robloxId=0,nameKey='shop.donation_s',descriptionKey='shop.donation_desc',support=1},
 {id='donation_m',robloxId=0,nameKey='shop.donation_m',descriptionKey='shop.donation_desc',support=1},
 {id='donation_l',robloxId=0,nameKey='shop.donation_l',descriptionKey='shop.donation_desc',support=1},
}
K.items={
 {id='classic',slot='kit',tokenCost=0,nameKey='shop.classic',descriptionKey='shop.kit_desc',colors={190,243,103},pattern='solid'},
 {id='lime',slot='kit',tokenCost=30,nameKey='shop.lime',descriptionKey='shop.kit_desc',colors={125,235,151},pattern='stripe'},
 {id='sunset',slot='kit',tokenCost=60,nameKey='shop.sunset',descriptionKey='shop.kit_desc',colors={255,144,91},pattern='sash'},
 {id='hoops',slot='kit',pass='identity',nameKey='shop.hoops',descriptionKey='shop.kit_desc',colors={88,185,246},pattern='hoops'},
 {id='crest_star',slot='crest',pass='identity',nameKey='shop.crest_star',descriptionKey='shop.crest_desc',shape='star'},
 {id='night',slot='stadium',tokenCost=80,nameKey='shop.night',descriptionKey='shop.stadium_cosmetic',pitchColors={20,69,62},lighting='night'},
 {id='designer',slot='stadium',pass='stadium',nameKey='shop.designer',descriptionKey='shop.stadium_cosmetic',pitchColors={34,104,76},lighting='floodlights'},
 {id='clean',slot='broadcast',tokenCost=0,nameKey='shop.clean',descriptionKey='shop.broadcast_cosmetic',accent={190,243,103}},
 {id='broadcast_pro',slot='broadcast',pass='broadcast',nameKey='shop.broadcast_pro',descriptionKey='shop.broadcast_cosmetic',accent={97,190,255}},
 {id='supporter_badge',slot='badge',pass='supporter',nameKey='shop.supporter_badge',descriptionKey='shop.badge_desc',colors={237,198,92}},
}
K.editorPalettes={{190,243,103},{87,157,219},{255,144,91},{164,93,183},{47,177,165},{237,198,92},{239,245,247},{22,32,48}}
K.maxTokens=1000000000
K.maxReceiptIdLength=160
return K
