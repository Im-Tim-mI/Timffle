package main

import (
	"context"
	"errors"
	"io"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const maxDialCandidates = 16

type lookupResult struct {
	addrs []net.IPAddr
	err   error
}
type dialResult struct {
	conn net.Conn
	err  error
}

// The standard resolver/dialer honor contexts. Keeping a select at the call
// boundary also prevents a slow platform resolver from holding serve hostage.
// There is only one lookup and at most maxDialCandidates attempts per process.
func lookupBounded(ctx context.Context, host string, lookup func(context.Context, string) ([]net.IPAddr, error)) ([]net.IPAddr, error) {
	ch := make(chan lookupResult, 1)
	go func() { a, e := lookup(ctx, host); ch <- lookupResult{a, e} }()
	select {
	case r := <-ch:
		return r.addrs, r.err
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

func dialBounded(ctx context.Context, address string, dial func(context.Context, string, string) (net.Conn, error)) (net.Conn, error) {
	ch := make(chan dialResult)
	go func() {
		c, e := dial(ctx, "tcp", address)
		select {
		case ch <- dialResult{c, e}:
		case <-ctx.Done():
			if c != nil {
				_ = c.Close()
			}
		}
	}()
	select {
	case r := <-ch:
		if ctx.Err() != nil {
			if r.conn != nil {
				_ = r.conn.Close()
			}
			return nil, ctx.Err()
		}
		if r.err != nil && r.conn != nil {
			_ = r.conn.Close()
			r.conn = nil
		}
		if r.conn == nil && r.err == nil {
			r.err = io.ErrUnexpectedEOF
		}
		return r.conn, r.err
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

func connectionTimeout(ms int64) time.Duration {
	if ms == 0 {
		return defaultTimeout
	}
	// Clamp BEFORE converting/multiplying to avoid duration overflow.
	ms = min(max(ms, int64(minTimeout/time.Millisecond)), int64(maxTimeout/time.Millisecond))
	return time.Duration(ms) * time.Millisecond
}

func openTCP(parent context.Context, req request, opt options) (net.Conn, string) {
	host := normalizeHost(req.Host)
	if host == "" || req.Port < 1 || req.Port > 65535 || req.TimeoutMs < 0 {
		return nil, "invalid"
	}
	if parent.Err() != nil {
		return nil, "timeout"
	}
	opt = opt.defaults()
	ctx, cancel := context.WithTimeout(parent, connectionTimeout(req.TimeoutMs))
	defer cancel()
	var addrs []net.IPAddr
	if ip := net.ParseIP(host); ip != nil {
		addrs = []net.IPAddr{{IP: ip}}
	} else {
		var err error
		addrs, err = lookupBounded(ctx, host, opt.lookup)
		if err != nil {
			if ctx.Err() != nil || errors.Is(err, context.DeadlineExceeded) {
				return nil, "timeout"
			}
			return nil, "dns"
		}
	}
	if ctx.Err() != nil {
		return nil, "timeout"
	}
	if len(addrs) == 0 {
		return nil, "dns"
	}

	// Validate ALL answers before truncation/deduplication. A private answer
	// after the candidate cap still poisons the entire DNS response. Pin copies
	// of the validated addresses and never pass a hostname to DialContext.
	ips := make([]netip.Addr, 0, min(len(addrs), maxDialCandidates))
	seen := make(map[netip.Addr]bool, maxDialCandidates)
	for _, a := range addrs {
		if ctx.Err() != nil {
			return nil, "timeout"
		}
		ip, ok := netip.AddrFromSlice(a.IP)
		if !ok || a.Zone != "" {
			return nil, "blocked"
		}
		ip = ip.Unmap()
		if !opt.allowPrivate && !isPublicIP(net.IP(ip.AsSlice())) {
			return nil, "blocked"
		}
		if !seen[ip] && len(ips) < maxDialCandidates {
			ips = append(ips, ip)
			seen[ip] = true
		}
	}
	// Bound every attempt to its fair share of the remaining TOTAL budget.
	// A black-holed first address cannot consume the fallback candidates' time.
	code := "unreachable"
	deadline, _ := ctx.Deadline()
	for i, ip := range ips {
		if ctx.Err() != nil {
			return nil, "timeout"
		}
		share := time.Until(deadline) / time.Duration(len(ips)-i)
		if share <= 0 {
			return nil, "timeout"
		}
		attempt, stop := context.WithTimeout(ctx, share)
		c, err := dialBounded(attempt, net.JoinHostPort(ip.String(), strconv.Itoa(req.Port)), opt.dial)
		attemptErr := attempt.Err()
		stop()
		if err == nil {
			if ctx.Err() != nil {
				_ = c.Close()
				return nil, "timeout"
			}
			return c, ""
		}
		if ctx.Err() != nil {
			return nil, "timeout"
		}
		var ne net.Error
		if attemptErr != nil || errors.Is(err, context.DeadlineExceeded) || (errors.As(err, &ne) && ne.Timeout()) {
			code = "timeout"
		} else if isRefused(err) && code != "timeout" {
			code = "refused"
		}
	}
	return nil, code
}

// Windows has WSAECONNREFUSED rather than syscall.ECONNREFUSED.
func isRefused(err error) bool {
	return errors.Is(err, syscall.ECONNREFUSED) || strings.Contains(strings.ToLower(err.Error()), "refused")
}
