## The work that comes in over the old computer: who's calling, what they want, what it pays,
## and everything the customer says along the way. Each job also picks its property and tree.
class_name Jobs
extends RefCounted

## playtest switch: every job open from the start, and the wedges + bull rope are
## lent for free so the gear-gated jobs work. Set false to bring the career locks back.
const ALL_OPEN := true

const EARL := {
	id = "earl", n = 1, title = "Earl's dead ash", pay = 400, unlock = 0, look = "earl", who = "Earl",
	text = "Old fella out on Birch Rd. Dead ash in the yard, leaning. Drop it, limb it, chip the brush, stack the rounds behind his shed.",
	tree_word = "dead ash", bark_tint = Color(1, 1, 1),
	talk = [
		"Well it's about dang time! You the tree fella? You look like a tree fella.",
		"That ash out back's deader'n disco. Them little green beetles got it. Emerald ash borers, the TV called 'em.",
		"It creaks at me every night. Every. Night. Like it's plottin' somethin'.",
		"Here's the deal: drop it, chip the branches, and cut the trunk into rounds I can lift. Pile 'em up out behind my shed.",
		"Four hundred bucks, cash. From my mattress. Don't ask about the mattress.",
		"Go on, git! And don't drop it on my house."],
	idle = [
		"Did I ever tell ya about the squirrel that robbed me? Took a whole bag of peanuts. Looked me dead in the eye.",
		"Them little green beetles came all the way here just to ruin MY tree. I take that personal.",
		"My cousin Del didn't watch his hinge. Now he sells insurance.",
		"Don't mind the chickens. Wait, I don't have chickens. Whose chickens are those?",
		"That tree's been creakin' at me every night for two years. Plottin', I tell ya.",
		"You want a coffee? I don't have coffee. Just askin' if you WANT one.",
		"Back in my day we cut trees with a butter knife and a positive attitude."],
	porch = "I'll be on the porch! If that thing lands on my house I'm keepin' your truck!",
	fell = ["WHOOO-EE! Did ya feel that in your boots?!", "Timber! I always wanted to yell that.", "Lord, that was louder than my ex-wife."],
	barber = "Holy smokes! It split right up the middle!",
	done = "Hey! Looks done to me! Come get your money!",
	paid = ["Well I'll be. Look at that. Neat as a pin!", "Here's your money. Mostly twenties. One's Canadian, don't ask.",
		"I got a buddy with a whole yard of sick maples. I'll put in a good word. Maybe."],
	hit_house = "MY HOUSE! That's comin' outta your money, hotshot!",
	hit_garage = "",
}

const HALE := {
	id = "hale", n = 2, title = "Widow Hale's leaning maple", pay = 650, unlock = 1, needs = "wedges", look = "hale", who = "Mrs. Hale",
	text = "Mrs. Hale on Cedar Ln (Earl's buddy, sort of). Dead sugar maple leaning hard at her garage. It has to go the other way. Load the rounds in Walter's old utility trailer and tarp it. She says you can keep the trailer, and the firewood. Bring wedges. A pull rope wouldn't hurt.",
	tree_word = "dead maple", bark_tint = Color(0.93, 0.82, 0.72),
	talk = [
		"Oh good, you came. Earl said you were 'not the worst.' From Earl that's practically a medal.",
		"That sugar maple was Walter's. He planted it the summer we were married, 1971. It died last year, same as him. Stubborn, both of them.",
		"And see how it leans? Right at the garage. Walter's Buick is in there. I don't drive it. I just like that it's there.",
		"So it can't go that way. It goes out across the lawn, away from the garage. Can you do that?",
		"Earl said a tree that leans like that sits back on you. You'll want wedges in the back cut, or a rope on it. Maybe both. I wrote it down.",
		"Six hundred fifty dollars. Chip the branches, please. I hate a mess.",
		"And see Walter's old trailer by the drive? Cut the trunk into rounds and load them in there. Then throw the tarp over it so nothing bounces out on the road.",
		"You keep it. The trailer, the wood, all of it. Earl says you've got a fireplace. Walter would like that his tree's keeping somebody warm."],
	idle = [
		"Walter used to say a tree tells you where it wants to go. Then you tell it where it's going.",
		"I've made lemonade. It's mostly sugar. Walter liked it that way.",
		"Don't mind the gnome. His name is Gerald. He's seen things.",
		"Earl called me twice to ask if you'd come yet. That man has nothing to do.",
		"That garage door sticks in the rain. Please don't make it stick worse.",
		"My grandson says I should 'get an app' for the tree. I don't know what that means."],
	porch = "I'll be on the porch with my lemonade. Mind the garage, dear. Mind. The. Garage.",
	fell = ["Oh my! Oh my goodness! Walter would have whooped.", "Well. That's that, then. Thank you, dear.", "Gerald and I felt that one in our bones."],
	barber = "Good heavens! It split right up the trunk! Are you all right?",
	done = "Yoo-hoo! It looks wonderful. Come get your money, dear!",
	paid = ["Oh, it's like the yard can breathe again.", "Here you are. I put it in a card. There's a twenty extra in there for being polite.",
		"Hitch that trailer up when you go. It's yours now. Walter kept it nice. Mostly.",
		"My sister on Lakeview has an oak hanging over her whole roof. I'll give her your number."],
	hit_house = "My HOUSE! Oh, Walter. Oh, the insurance man is going to have a field day.",
	hit_garage = "THE GARAGE! Walter's Buick! Oh, I need to sit down.",
}

const DOCK := {
	id = "dock", n = 3, title = "Gus's dock logs", pay = 800, unlock = 2, needs = "rope", look = "gus", who = "Gus", kind = "logs",
	text = "Gus on Loon Lake wants a new dock, and there's a raft of old logs sunk in the shallows right where it goes. Rope 'em, drag 'em out with the truck, buck 'em and load your trailer. Bring the bull rope.",
	tree_word = "logs", bark_tint = Color(0.72, 0.7, 0.66),
	talk = [
		"There he is! Mrs. Hale says you're the fella who didn't flatten Walter's Buick. High praise in this town.",
		"So. Forty years I've been meaning to build a proper dock. Forty years those logs have been sitting right where it goes.",
		"Old log-drive timber, they think. Sank in the shallows before my granddad's time. Water's about waist deep out there.",
		"Wade out, get your bull rope round one, hook it to your truck and drag it up the beach. Then buck 'em and load 'em in that trailer of yours.",
		"Eight hundred dollars. And if you do it right, I've got something better than money for you. Well. Almost as good.",
		"Mind the drop-off past the last stake. It's cold enough to stop a clock."],
	idle = [
		"There's a bass under that log the size of a mailbox. I've named him Gerald. No relation to Mrs. Hale's gnome.",
		"My wife says a man my age doesn't need a dock. My wife doesn't fish.",
		"Waders are cold, son. Cold and wet. That's the deal you make with the lake.",
		"I've been retired eleven years and I've never been busier. Nobody tells you that.",
		"You hear that loon? That's how you know you're home.",
		"Granddad said they floated a million feet of pine down this lake once. Guess a few didn't make it."],
	porch = "I'll be on the bench. Shout if you fall in. I won't help, but I'd like to know.",
	fell = ["There she comes!", "Look at that old girl. Must be a hundred years down there.", "Ha! Didn't think the lake'd let go of that one."],
	barber = "",
	done = "Well I'll be. Clear water where my dock goes! Come on over here.",
	paid = ["Forty years I've looked at those logs. Forty years. Thank you.", "Here's your eight hundred. And here, take this. My old spinning rod. She's caught more fish than I've had hot dinners.",
		"Creeks, lakes, wherever you're working. A tree man ought to know how to fish. Press 6 by the water and give her a cast."],
	hit_house = "My house! The logs were in the LAKE, son!",
	hit_garage = "",
}

const STORM := {
	id = "storm", n = 4, title = "Storm damage at the Mill Creek bridge", pay = 1100, unlock = 3, look = "sheriff", who = "Sheriff Boone", kind = "storm",
	text = "Sheriff's call. Last night's storm put four trees down across County Rd 9, right in front of the Mill Creek bridge. One's out roots and all. Sheriff Boone's holding the road shut. Limb them, chip the brush, buck the trunks and get every round off the road.",
	tree_word = "downed trees", bark_tint = Color(0.92, 0.9, 0.86),
	talk = [
		"You the tree outfit? Good. Sheriff Boone. I've been parked on this road since four this morning.",
		"Storm came through about two. Put four of 'em down right here, our side of the bridge. Nobody gets across to Mill Creek till they're gone.",
		"That big ash pulled up roots and all. The one on the south side snapped off like a pencil. Mind the springy limbs, they'll bite.",
		"Limb 'em, run the brush through your chipper, cut the trunks into rounds and get every last piece off the asphalt. Roll 'em in the ditch, I don't care. Just off my road.",
		"County pays eleven hundred. I'll sign the voucher myself the minute that road's open.",
		"And stay off that bridge rail. Creek's up after all that rain, and the falls are louder than my mother-in-law."],
	idle = [
		"Dispatch says the school bus needs this road by three. No pressure.",
		"Fella in a minivan tried to go around through the ditch. He's still in the ditch.",
		"Thirty-one years with the county and the weather's still the worst criminal I've got.",
		"They call that waterfall the Widow's Veil. Don't ask me why. Nobody ever tells me why.",
		"I'd help, but I'm management.",
		"Earl called the station to tell me you're 'not the worst.' I put it in the log.",
		"Coffee's cold. Coffee's always cold. That's police work."],
	porch = "I'll be by the cruiser keeping the road shut. Holler if you need traffic stopped.",
	fell = ["That's the way.", "Atta boy.", "Heard that one from here."],
	barber = "",
	done = "Well, would you look at that. Asphalt! Come on over and I'll sign you off.",
	paid = ["Road's open. I'll radio it in.", "Here's the county's eleven hundred. Voucher's signed. Don't lose it, they'll make me fill it out again.",
		"Next time something big comes down in this county, I'm calling you first."],
	hit_house = "",
	hit_garage = "",
}

const OAK := {
	id = "oak", n = 5, title = "The Kowalskis' backyard oak", pay = 1500, unlock = 4, needs = "climb", look = "dale", who = "Dale", kind = "climb",
	text = "Dale Kowalski on Lakeview (Mrs. Hale's sister's neighbor). A big red oak died of oak wilt, standing between the house, the back deck and the kids' swing set. It can't be felled whole: climb it, limb it, top it and bring it down in pieces. Bring the climbing kit.",
	tree_word = "dead oak", bark_tint = Color(0.8, 0.76, 0.7),
	fell_txt = "Take the oak down from the top: climb it, cut the limbs off, top it, then drop what's left",
	talk = [
		"You're the tree guy? Thank God. Mrs. Hale's sister said you're the only one in the county who didn't laugh at her.",
		"So that's the oak. Oak wilt, the DNR guy said. Went brown in July and that was that. My dad planted it when I was a kid.",
		"Problem is where it is. House on one side, the deck on the other, and the kids' swing set right there. You can't just tip it over. Can you?",
		"Didn't think so. You've got the climbing stuff? Good. Take it down a piece at a time. The lawn strip out back toward the fence is about the only open ground.",
		"Fifteen hundred. And hey, if you can save me one good slice out of the trunk, my wife wants a table top. No pressure.",
		"Kids are at their grandma's. Go for it."],
	idle = [
		"My dad used to say an oak takes a hundred years to grow and a hundred to die. This one did it in a summer.",
		"The DNR guy said don't move the wood before it's dried out. Something about beetles carrying the fungus. I wrote it down. Somewhere.",
		"You ever fall out of one of those? Don't answer that.",
		"The swing set was a Christmas present. Three hours to put together. Two of them were swearing.",
		"My wife is watching from the kitchen window. She says hi. She also says mind the deck.",
		"How do you guys get up there with those spike things? My knees hurt just looking."],
	porch = "I'll be on the deck. Unless you're dropping stuff on the deck. Then I'll be in the driveway.",
	fell = ["There it goes! Hey, the yard looks huge!", "Whoa. That's a lot of tree.", "Ha! Right where you said. How do you DO that?"],
	barber = "Whoa, it ripped right up the middle! You okay?",
	done = "That's it? Yard's clear! Come on over, I'll get my checkbook.",
	paid = ["I can see the lake from the deck again. I forgot you could.", "Fifteen hundred, and a little extra for the table slice.",
		"My buddy's the caretaker out at the township cemetery. Big old spruce dying in there, right in with the graves. I'll tell him to call you."],
	hit_house = "THE HOUSE! Oh no. Oh no no no. My wife saw that.",
	hit_garage = "",
	hits = {deck = "The deck! I just stained that!", swing = "Aw, not the swing set! The kids are gonna kill me.", fence = "There goes the fence. Well. It was ugly anyway."},
}

const CEMETERY := {
	id = "cemetery", n = 6, title = "The township cemetery spruce", pay = 1800, unlock = 5, needs = "lowrig", look = "keeper", who = "Arlo", kind = "climb",
	text = "Arlo, the caretaker at Maple Grove Cemetery off Mill Rd. A dead Norway spruce standing right in among the graves. Nothing gets dropped: every limb and every piece of trunk comes down on a rope. The founder's family plot is under the north side. Bring the climbing kit and the lowering rig.",
	tree_word = "dead spruce", bark_tint = Color(0.86, 0.8, 0.76),
	fell_txt = "Take the spruce down from the top, lowering everything on the rope, then drop what's left",
	pile_txt = "Buck the stem into liftable rounds and stack them outside the gate",
	talk = [
		"Afternoon. Arlo Lindgren. Thirty-two years caretaker out here. Dale Kowalski says you're careful. That's the only kind I can use.",
		"That spruce went in when the chapel burned in 1931. Needles went brown two summers ago and never came back.",
		"Look around it. Stones on every side. Some of these families still come out every Memorial Day. Some of these stones, there's nobody left to replace them.",
		"So nothing comes down free. Everything on a rope, down to the gravel. The aisle's the only place I'll let you set wood on.",
		"And the north side, that's the Halverson plot. The obelisk. Founder of the township. Please. Not the obelisk.",
		"Eighteen hundred from the township board. I'll sign for it myself."],
	idle = [
		"People think a cemetery's a sad place. It's the quietest place in the county. I like it.",
		"Some of these stones are older than the state. Michigan, I mean. Not the cemetery.",
		"I had a fella in here with a stump grinder once. Once.",
		"The squirrels in here are fat. Nobody chases them.",
		"Halverson came over in 1868 and cleared this whole section by hand. Then they buried him in it. That's a pioneer for you.",
		"Take your time. Nobody here's in a hurry."],
	porch = "I'll be by the gate. Holler if you need me.",
	fell = ["Well. That's done, then.", "Easy does it. That's how it's done.", "Halverson would've liked that."],
	barber = "Oh, my. It split. Everyone all right?",
	done = "Not a stone out of place. Come on over, I'll sign you off.",
	paid = ["Thirty-two years, I've never seen it done that careful.", "Here's the township's eighteen hundred. I put a thank-you note in with it. Board doesn't know about the note.",
		"You ever need a quiet place to eat your lunch, the gate's always open."],
	hit_house = "",
	hit_garage = "",
	hits = {stone = "Oh, no. That's the Petersons'. That stone's been there since 1902.", plot = "The obelisk! Lord, the Halverson obelisk!", fence = "Watch the fence there."},
}

const LIST := [EARL, HALE, DOCK, STORM, OAK, CEMETERY]

## the job list for the computer, open or locked by how many jobs you've done
static func board(jobs_done: int) -> Array:
	var out := []
	var c := Career.load()
	for j in LIST:
		var open: bool = ALL_OPEN or jobs_done >= int(j.unlock)
		var text: String = j.text if open else "Finish %d job%s first. Word gets around." % [j.unlock, "" if j.unlock == 1 else "s"]
		# some jobs need gear you have to buy first
		var need: String = j.get("needs", "")
		if not ALL_OPEN and open and need != "" and not bool(c.get(need, false)):
			open = false
			text = j.text + "  >> BUY THE %s (UPGRADES TAB) BEFORE YOU TAKE THIS ONE." % {"wedges": "FELLING WEDGES", "rope": "BULL ROPE", "climb": "CLIMBING KIT", "lowrig": "LOWERING RIG"}.get(need, need.to_upper())
		out.append({title = j.title, pay = j.pay, open = open, text = text})
	out.append({title = "-- nothing else yet --", pay = 0, open = false, text = "Check back after a job or two."})
	return out
