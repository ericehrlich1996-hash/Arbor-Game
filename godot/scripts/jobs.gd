## The work that comes in over the old computer: who's calling, what they want, what it pays,
## and everything the customer says along the way. Each job also picks its property and tree.
class_name Jobs
extends RefCounted

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
	id = "hale", n = 2, title = "Widow Hale's leaning maple", pay = 650, unlock = 1, look = "hale", who = "Mrs. Hale",
	text = "Mrs. Hale on Cedar Ln (Earl's buddy, sort of). Dead sugar maple leaning hard at her garage. It has to go the other way. Bring wedges. A pull rope wouldn't hurt.",
	tree_word = "dead maple", bark_tint = Color(0.93, 0.82, 0.72),
	talk = [
		"Oh good, you came. Earl said you were 'not the worst.' From Earl that's practically a medal.",
		"That sugar maple was Walter's. He planted it the summer we were married, 1971. It died last year, same as him. Stubborn, both of them.",
		"And see how it leans? Right at the garage. Walter's Buick is in there. I don't drive it. I just like that it's there.",
		"So it can't go that way. It goes out across the lawn, away from the garage. Can you do that?",
		"Earl said a tree that leans like that sits back on you. You'll want wedges in the back cut, or a rope on it. Maybe both. I wrote it down.",
		"Six hundred fifty dollars. Cut the trunk into rounds I can roll and stack them by the shed for the fire pit. And chip the branches, please. I hate a mess."],
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
		"My sister on Lakeview has an oak hanging over her whole roof. I'll give her your number."],
	hit_house = "My HOUSE! Oh, Walter. Oh, the insurance man is going to have a field day.",
	hit_garage = "THE GARAGE! Walter's Buick! Oh, I need to sit down.",
}

const LIST := [EARL, HALE]

## the job list for the computer, open or locked by how many jobs you've done
static func board(jobs_done: int) -> Array:
	var out := []
	for j in LIST:
		var open: bool = jobs_done >= int(j.unlock)
		out.append({title = j.title, pay = j.pay, open = open,
			text = j.text if open else "Finish %d job%s first. Word gets around." % [j.unlock, "" if j.unlock == 1 else "s"]})
	out.append({title = "-- nothing else yet --", pay = 0, open = false, text = "Check back after a job or two."})
	return out
