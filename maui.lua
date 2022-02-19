-- Helper script to make an easier startup command without breaking people already using ma/start
local mq = require('mq')
mq.cmd('/lua run ma/start')