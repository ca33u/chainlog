--[[
  Chainlog: strings. English is the key; other languages map from it.
]]

local _, ns = ...

local L = {}
ns.L = L

local RU = {
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
	["Click: waypoint to the quest giver"] = "Клик: метка на карте к квестодателю",
	["Click: waypoint to where you turn it in"] = "Клик: метка на карте к месту сдачи",
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
	["off"] = "выкл",
}

local active = (GetLocale and GetLocale() == "ruRU") and RU or nil

function ns.T(text)
	return active and active[text] or text
end
ns.RU = RU
