//go:build !localtest

package main

// No production environment variable or request can relax address policy.
func localTestPrivatePermission() bool { return false }
