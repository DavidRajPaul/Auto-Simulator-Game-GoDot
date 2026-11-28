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
## A banner appeared on screen or went away (screens move their bottom row clear of it).
signal banner_visibility_changed(visible: bool)

## Standard banner height (AdMob BANNER = 320 x 50 dp), anchored at the bottom centre.
const BANNER_W_DP: float = 320.0
const BANNER_H_DP: float = 50.0

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

## Show (true) or hide (false) the bottom banner. Loads one first if needed; a banner that
## fails to load simply never appears.
func show_banner(_visible: bool) -> void:
	pass

## True only while a banner is actually on screen (loaded and shown).
func is_banner_showing() -> bool:
	return false

func provider_name() -> String:
	return "none"
