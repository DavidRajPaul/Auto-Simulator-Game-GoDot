class_name AdProvider
extends Node
## Ad network interface. AdMonetizationManager talks only to this, so swapping the mock
## placeholder for AdMob / AppLovin MAX is one line in data/monetization/ad_config.tres.
##
## Contract: load_*() pre-fetches silently; show_*() returns false at once when nothing is
## loaded (the game NEVER waits on an ad — 0 ms blocking, per the tech spec). Results arrive
## through the signals; `earned` is only emitted when the network confirms the reward.

signal rewarded_earned(placement: String)
signal rewarded_closed(placement: String)
signal rewarded_failed(placement: String, reason: String)
signal interstitial_closed(placement: String)

var config: AdConfig

func setup(cfg: AdConfig) -> void:
	config = cfg

func load_rewarded() -> void:
	pass

func load_interstitial() -> void:
	pass

func is_rewarded_ready() -> bool:
	return false

func is_interstitial_ready() -> bool:
	return false

func show_rewarded(_placement: String) -> bool:
	return false

func show_interstitial(_placement: String) -> bool:
	return false

func show_banner(_visible: bool) -> void:
	pass

func provider_name() -> String:
	return "none"
