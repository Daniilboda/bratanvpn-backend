// BratanVPN Windows tunnel helper.
//
// Runs as a LocalSystem service and exposes a named pipe so the Flutter UI
// can start/stop the AmneziaWG tunnel without elevating on every click.
//
// Commands:
//
//	bratanvpn_helper.exe install    — copy binaries + create/start service (needs admin / UAC)
//	bratanvpn_helper.exe uninstall  — stop/delete service (needs admin)
//	bratanvpn_helper.exe service    — SCM entrypoint (do not run manually)
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/Microsoft/go-winio"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"
)

const (
	serviceName = "BratanVpnHelper"
	displayName = "BratanVPN Tunnel Helper"
	pipePath    = `\\.\pipe\BratanVpnHelper`
	// Authenticated users may talk to the pipe; SYSTEM/Admins full control.
	pipeSDDL = "D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;AU)"
	tunnelName = "bratanvpn"
	installDir = `C:\ProgramData\BratanVPN`
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "usage: %s install|uninstall|service\n", filepath.Base(os.Args[0]))
		os.Exit(2)
	}

	switch strings.ToLower(os.Args[1]) {
	case "install":
		if err := cmdInstall(); err != nil {
			fatal(err)
		}
	case "uninstall":
		if err := cmdUninstall(); err != nil {
			fatal(err)
		}
	case "service":
		if err := svc.Run(serviceName, &helperService{}); err != nil {
			fatal(err)
		}
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		os.Exit(2)
	}
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, err.Error())
	os.Exit(1)
}

func cmdInstall() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	exe, err = filepath.Abs(exe)
	if err != nil {
		return err
	}
	exeDir := filepath.Dir(exe)

	// Stop helper service first so ProgramData binaries can be replaced and the
	// new process actually loads on start (in-memory old exe would otherwise stay).
	if err := stopHelperService(); err != nil {
		return err
	}

	if err := os.MkdirAll(installDir, 0o755); err != nil {
		return err
	}

	amneziaSrc, err := findAmneziaSourceDir(exeDir)
	if err != nil {
		return err
	}

	for _, name := range []string{"amneziawg.exe", "wintun.dll", "awg.exe"} {
		from := filepath.Join(amneziaSrc, name)
		if _, err := os.Stat(from); err != nil {
			if name == "awg.exe" {
				continue
			}
			return fmt.Errorf("missing %s in %s", name, amneziaSrc)
		}
		to := filepath.Join(installDir, name)
		if err := copyFile(from, to); err != nil {
			return fmt.Errorf("copy %s: %w", name, err)
		}
	}

	helperDst := filepath.Join(installDir, "bratanvpn_helper.exe")
	if err := copyFile(exe, helperDst); err != nil {
		return fmt.Errorf("copy helper: %w", err)
	}

	m, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer m.Disconnect()

	s, err := m.OpenService(serviceName)
	if err == nil {
		s.Close()
		return startService()
	}

	s, err = m.CreateService(
		serviceName,
		helperDst,
		mgr.Config{
			DisplayName: displayName,
			StartType:   mgr.StartAutomatic,
			Description: "Starts and stops the BratanVPN AmneziaWG tunnel without per-click UAC.",
		},
		"service",
	)
	if err != nil {
		return err
	}
	s.Close()
	return startService()
}

func stopHelperService() error {
	m, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer m.Disconnect()

	s, err := m.OpenService(serviceName)
	if err != nil {
		return nil // not installed yet
	}
	defer s.Close()

	_, _ = s.Control(svc.Stop)
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		st, qErr := s.Query()
		if qErr != nil || st.State == svc.Stopped {
			return nil
		}
		time.Sleep(200 * time.Millisecond)
	}
	return fmt.Errorf("helper service did not stop")
}

func findAmneziaSourceDir(helperExeDir string) (string, error) {
	candidates := []string{
		filepath.Join(helperExeDir, "amneziawg"),
		helperExeDir,
		installDir,
	}
	for _, dir := range candidates {
		if _, err := os.Stat(filepath.Join(dir, "amneziawg.exe")); err == nil {
			return dir, nil
		}
	}
	return "", fmt.Errorf("amneziawg.exe not found next to helper; rebuild Windows client with sidecar")
}

func cmdUninstall() error {
	_ = runAmnezia("/uninstalltunnelservice", tunnelName)

	m, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer m.Disconnect()

	s, err := m.OpenService(serviceName)
	if err != nil {
		return nil // already gone
	}
	defer s.Close()

	_, _ = s.Control(svc.Stop)
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		st, err := s.Query()
		if err != nil || st.State == svc.Stopped {
			break
		}
		time.Sleep(200 * time.Millisecond)
	}
	return s.Delete()
}

func startService() error {
	m, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer m.Disconnect()
	s, err := m.OpenService(serviceName)
	if err != nil {
		return err
	}
	defer s.Close()
	st, err := s.Query()
	if err != nil {
		return err
	}
	if st.State == svc.Running {
		return nil
	}
	return s.Start()
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o755)
	if err != nil {
		return err
	}
	defer out.Close()
	if _, err := io.Copy(out, in); err != nil {
		return err
	}
	return out.Close()
}

type helperService struct{}

func (h *helperService) Execute(args []string, r <-chan svc.ChangeRequest, changes chan<- svc.Status) (bool, uint32) {
	changes <- svc.Status{State: svc.StartPending}
	stopPipe := make(chan struct{})
	go servePipe(stopPipe)
	changes <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}

	for c := range r {
		switch c.Cmd {
		case svc.Stop, svc.Shutdown:
			close(stopPipe)
			changes <- svc.Status{State: svc.StopPending}
			return false, 0
		case svc.Interrogate:
			changes <- c.CurrentStatus
		}
	}
	return false, 0
}

func servePipe(stop <-chan struct{}) {
	for {
		select {
		case <-stop:
			return
		default:
		}

		cfg := &winio.PipeConfig{
			SecurityDescriptor: pipeSDDL,
			MessageMode:        false,
		}
		listener, err := winio.ListenPipe(pipePath, cfg)
		if err != nil {
			time.Sleep(time.Second)
			continue
		}

		done := make(chan struct{})
		go func() {
			select {
			case <-stop:
			case <-done:
			}
			_ = listener.Close()
		}()

		for {
			conn, err := listener.Accept()
			if err != nil {
				close(done)
				select {
				case <-stop:
					return
				default:
					time.Sleep(500 * time.Millisecond)
				}
				break
			}
			go handleConn(conn)
		}
	}
}

func handleConn(c io.ReadWriteCloser) {
	defer c.Close()
	reader := bufio.NewReader(c)
	line, err := reader.ReadString('\n')
	if err != nil {
		return
	}
	line = strings.TrimSpace(line)
	parts := strings.SplitN(line, " ", 2)
	cmd := strings.ToUpper(parts[0])

	var resp string
	switch cmd {
	case "PING":
		resp = "PONG"
	case "STATUS":
		if tunnelRunning() {
			resp = "RUNNING"
		} else {
			resp = "STOPPED"
		}
	case "START":
		if len(parts) < 2 || strings.TrimSpace(parts[1]) == "" {
			resp = "ERR missing conf path"
			break
		}
		conf := strings.TrimSpace(parts[1])
		if err := startTunnel(conf); err != nil {
			resp = "ERR " + err.Error()
		} else {
			resp = "OK"
		}
	case "STOP":
		if err := stopTunnel(); err != nil {
			resp = "ERR " + err.Error()
		} else {
			resp = "OK"
		}
	default:
		resp = "ERR unknown command"
	}
	_, _ = io.WriteString(c, resp+"\n")
}

func amneziaExe() string {
	return filepath.Join(installDir, "amneziawg.exe")
}

func runAmnezia(args ...string) error {
	cmd := exec.Command(amneziaExe(), args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		msg := strings.TrimSpace(string(out))
		if msg == "" {
			msg = err.Error()
		}
		return fmt.Errorf("%s", msg)
	}
	return nil
}

func isTunnelAbsentErr(err error) bool {
	if err == nil {
		return false
	}
	low := strings.ToLower(err.Error())
	return strings.Contains(low, "cannot find") ||
		strings.Contains(low, "not found") ||
		strings.Contains(low, "does not exist")
}

func isAlreadyInstalledErr(err error) bool {
	if err == nil {
		return false
	}
	low := strings.ToLower(err.Error())
	return strings.Contains(low, "already installed") ||
		strings.Contains(low, "already running")
}

// ensureTunnelRemoved uninstalls the AmneziaWG tunnel service and waits until
// it is no longer RUNNING. Safe if the tunnel was never installed.
func ensureTunnelRemoved() error {
	err := runAmnezia("/uninstalltunnelservice", tunnelName)
	if err != nil && !isTunnelAbsentErr(err) {
		// Keep trying the wait loop — uninstall may have partially worked.
	}

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if !tunnelRunning() {
			return nil
		}
		_ = runAmnezia("/uninstalltunnelservice", tunnelName)
		time.Sleep(300 * time.Millisecond)
	}
	if tunnelRunning() {
		return fmt.Errorf("could not remove existing tunnel service")
	}
	return nil
}

func waitTunnelRunning(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if tunnelRunning() {
			return nil
		}
		time.Sleep(300 * time.Millisecond)
	}
	return fmt.Errorf("tunnel service did not reach RUNNING")
}

func installTunnelService(confPath string) error {
	err := runAmnezia("/installtunnelservice", confPath)
	if err == nil {
		return nil
	}
	if !isAlreadyInstalledErr(err) {
		return err
	}
	// Stale service still present — remove and retry once.
	if remErr := ensureTunnelRemoved(); remErr != nil {
		return fmt.Errorf("%v; remove retry: %v", err, remErr)
	}
	return runAmnezia("/installtunnelservice", confPath)
}

func startTunnel(confPath string) error {
	if _, err := os.Stat(confPath); err != nil {
		return fmt.Errorf("conf not found: %w", err)
	}
	if err := ensureTunnelRemoved(); err != nil {
		return err
	}
	if err := installTunnelService(confPath); err != nil {
		return err
	}
	if err := waitTunnelRunning(8 * time.Second); err != nil {
		_ = ensureTunnelRemoved()
		return err
	}
	return nil
}

func stopTunnel() error {
	if err := ensureTunnelRemoved(); err != nil {
		return err
	}
	return nil
}

func tunnelRunning() bool {
	cmd := exec.Command("sc.exe", "query", "AmneziaWGTunnel$"+tunnelName)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToUpper(string(out)), "RUNNING")
}
