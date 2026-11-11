--[[
  Chainlog: strings. English is the key; other languages map from it.
]]

local _, ns = ...

local L = {}
ns.L = L

local RU = {
	["On the map: %s"] = "На карте: %s",
	["Click: show where to turn it in on the map"] = "Клик: показать на карте, где сдать",
	["Click: show the quest giver on the map"] = "Клик: показать на карте, где взять",
	["Shift-click: open in your quest log"] = "Shift+клик: открыть в журнале заданий",
	["Click: show on the map  ·  Shift-click: quest log"] = "Клик: показать на карте  ·  Shift+клик: журнал",
	["Dungeons"] = "Подземелья",
	["My quests"] = "Мои квесты",
	["Hide completed"] = "Скрыть выполненные",
	["Show all levels"] = "Все уровни",
	["Entrance"] = "Вход",
	["Quest giver"] = "Выдаёт",
	["Turn in"] = "Сдать",
	["Starts from item"] = "Начинается с предмета",
	["inside the dungeon"] = "внутри подземелья",
	["done"] = "выполнен",
	["in log"] = "в журнале",
	["ready to turn in"] = "можно сдать",
	["available"] = "доступен",
	["needs level %d"] = "нужен %d уровень",
	["locked: finish the previous step"] = "закрыт: сначала прошлый шаг",
	["not needed any more"] = "уже не нужен",
	["optional lead-in"] = "необязательная подводка",
	["Requires"] = "Требует",
	["Leads to"] = "Открывает",
	["Waypoint set: %s"] = "Метка поставлена: %s",
	["No location known for this quest"] = "Место для этого квеста неизвестно",
	["Building the quest index..."] = "Собираю базу квестов...",
	["No dungeon quests for your faction and class here."] = "Здесь нет квестов для вашей фракции и класса.",
	["None of your quests belong to a chain."] = "Ни один ваш квест не входит в цепочку.",
	["QuestieDB is not loaded: Chainlog needs it for quest data."] = "QuestieDB не загружена: Chainlog берёт из неё данные о квестах.",
	["Chain quest"] = "Квест из цепочки",
	["Step %d of %d in a chain that leads to: %s"] = "Шаг %d из %d в цепочке, которая ведёт к: %s",
	["Dungeon quest: %s"] = "Квест для подземелья: %s",
	["To take it again: %s"] = "Взять заново: %s",
	["Abandoning keeps the earlier steps done, but this one must be picked up again."] = "Прошлые шаги останутся выполненными, но этот квест придётся взять заново.",
	["Abandoning it locks the next steps: %s"] = "Без него закроются следующие шаги: %s",
	["OK"] = "Понятно",
	["Left-click: open Chainlog"] = "ЛКМ: открыть Chainlog",
	["Drag: move the button"] = "Перетащить: сдвинуть кнопку",
	["chain"] = "цепочка",
	["step %d/%d"] = "шаг %d/%d",
	["Press Cmd+C (Ctrl+C) to copy the address"] = "Нажмите Cmd+C (Ctrl+C), чтобы скопировать адрес",
	["Click to copy the address"] = "Щёлкните, чтобы скопировать адрес",
	["by"] = "от",
	["abandon warning:"] = "предупреждение при отказе:",
	["minimap button:"] = "кнопка у миникарты:",
	["on"] = "вкл",
	["Inside: what your quests need"] = "Внутри: что нужно по вашим квестам",
	["from mobs in the dungeon"] = "с мобов подземелья",
	["dungeon checklist:"] = "чеклист в подземелье:",
	["talk"] = "поговорить",
	["kill"] = "убить",
	["use"] = "использовать",
	["loot"] = "добыть",
	["for"] = "для",
	["Lead"] = "Вести",
	["Stop"] = "Стоп",
	["Lead me through this chain"] = "Вести по этой цепочке",
	["Stop leading"] = "Перестать вести",
	["TomTom's arrow (or the map pin) moves to the next quest giver, objective and turn-in by itself."] = "Стрелка TomTom (или метка на карте) сама переходит к следующему квестодателю, цели задания и месту сдачи.",
	["Leading: %s"] = "Веду по цепочке: %s",
	["Stopped leading."] = "Больше не веду по цепочке.",
	["Chain finished!"] = "Цепочка пройдена!",
	["Take: %s"] = "Взять: %s",
	["Do: %s"] = "Выполнить: %s",
	["Turn in: %s"] = "Сдать: %s",
	["%s opens at level %d"] = "%s откроется на %d уровне",
	["%s: an earlier step is missing"] = "%s: не хватает прошлого шага",
	["Not leading any chain. Press Lead on a chain in /chainlog."] = "Сейчас ни одна цепочка не ведётся. Нажмите «Вести» у цепочки в /chainlog.",
	["off"] = "выкл",
}

local active = (GetLocale and GetLocale() == "ruRU") and RU or nil

function ns.T(text)
	return active and active[text] or text
end
ns.RU = RU
