package yugabyte

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

// Global Variables
var awsRegion, sshUser, yugabyteDir string
var ec2KeyPair *aws.Ec2Keypair
var maxRetries = 10
var timeBetweenRetries = 5 * time.Second

func TestYugaByteAwsTerraform(t *testing.T) {
	t.Parallel()

	yugabyteDir := test_structure.CopyTerraformFolderToTemp(t, "..", "../terraform-aws-yugabyte")

	defer test_structure.RunTestStage(t, "teardown", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, yugabyteDir)
		terraform.Destroy(t, terraformOptions)
		aws.DeleteEC2KeyPairE(t, ec2KeyPair)
		os.RemoveAll(yugabyteDir)
	})

	test_structure.RunTestStage(t, "SetUp", func() {
		var terraformOptions *terraform.Options
		terraformOptions, ec2KeyPair = configureTerraformOptions(t, yugabyteDir)
		test_structure.SaveTerraformOptions(t, yugabyteDir, terraformOptions)
		terraform.InitAndApply(t, terraformOptions)
	})

	test_structure.RunTestStage(t, "validate", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, yugabyteDir)
		ec2PublicIP := terraform.Output(t, terraformOptions, "public_ips")
		ec2PrivateIP := terraform.Output(t, terraformOptions, "private_ips")
		hostsPublicIP := strings.Fields(strings.Trim(ec2PublicIP, "[]\"\""))
		hostsPrivateIP := strings.Fields(strings.Trim(ec2PrivateIP, "[]\"\""))
		sshUser := terraform.Output(t, terraformOptions, "ssh_user")

		var publicIP, privateIP string
		for index, host := range hostsPublicIP {
			publicIP = strings.Trim(host, "\"\",")
			privateIP = strings.Trim(hostsPrivateIP[index], "\"\",")

			logger.Logf(t, "Host is :- Public IP: %s, Private IP: %s", publicIP, privateIP)

			sshHost := ssh.Host{
				Hostname:    publicIP,
				SshUserName: sshUser,
				SshKeyPair:  ec2KeyPair.KeyPair,
			}

			if index == 0 {
				testYugaByteMasterURL(t, terraformOptions, privateIP, sshHost)
				testYugaByteTserverURL(t, terraformOptions, privateIP, sshHost)
			}

			testYugaByteSSH(t, terraformOptions, sshHost)
			testYugaByteYSQLSH(t, terraformOptions, privateIP, sshUser, sshHost)
			testYugaByteCQLSH(t, terraformOptions, privateIP, sshUser, sshHost)
			testYugaByteConf(t, terraformOptions, sshUser, yugabyteDir, sshHost)
			testYugaByteProcess(t, terraformOptions, sshHost)
			testYugaByteLogFile(t, terraformOptions, sshUser, sshHost)
			testYugaByteNodeUlimit(t, terraformOptions, sshHost)
		}
	})
}

func configureTerraformOptions(t *testing.T, yugabyteDir string) (*terraform.Options, *aws.Ec2Keypair) {
	awsRegion = os.Getenv("AWS_REGION")
	uniqueID := os.Getenv("GITHUB_RUN_ID")
	clusterName := fmt.Sprintf("terratest-%s", uniqueID)
	allowedSources := strings.Split(os.Getenv("ALLOWED_SOURCES"), ",")
	sshKeyPairName := fmt.Sprintf("terratest-example-%s", uniqueID)
	ec2Key := aws.CreateAndImportEC2KeyPair(t, awsRegion, sshKeyPairName)
	privateKey := []byte(ec2Key.KeyPair.PrivateKey)
	privateKeyPath := filepath.Join(yugabyteDir, sshKeyPairName) + ".pem"
	err := ioutil.WriteFile(privateKeyPath, privateKey, 0400)
	if err != nil {
		t.Fatalf("Failed to save key to %s: %v", privateKeyPath, err)
	}
	vpcID := os.Getenv("VPC_ID")
	availabilityZones := strings.Split(os.Getenv("AVAILABILITY_ZONES"), ",")
	subnetID := strings.Split(os.Getenv("SUBNET_IDS"), ",")

	terraformOptions := &terraform.Options{
		TerraformDir: yugabyteDir,

		Vars: map[string]interface{}{
			"cluster_name":       clusterName,
			"ssh_keypair":        sshKeyPairName,
			"ssh_private_key":    privateKeyPath,
			"region_name":        awsRegion,
			"vpc_id":             vpcID,
			"availability_zones": availabilityZones,
			"subnet_ids":         subnetID,
			"allowed_sources":    allowedSources,
		},
	}
	return terraformOptions, ec2Key
}

// Verify the status of Master UI
func testYugaByteMasterURL(t *testing.T, terraformOptions *terraform.Options, masterUI string, sshSession ssh.Host) {
	statusCodeCheckCmd := fmt.Sprintf("curl -o /dev/null -s -w \"%%{http_code}\\n\" http://%s:7000", masterUI)
	bodyURLCmd := fmt.Sprintf("curl http://%s:7000", masterUI)
	retry.DoWithRetry(t, "Checking YB Master UI", maxRetries, timeBetweenRetries, func() (string, error) {
		outputStatus, errStatus := ssh.CheckSshCommandE(t, sshSession, statusCodeCheckCmd)
		if errStatus != nil {
			return "", errStatus
		}

		outputBody, errBody := ssh.CheckSshCommandE(t, sshSession, bodyURLCmd)
		if errBody != nil {
			return "", errBody
		}

		if !strings.Contains(string(outputBody), "YugabyteDB Version") {
			return "", fmt.Errorf("Failed to find the 'YugabyteDB Version' in output\nStatus Code: %s, Out from Master UI: %s", outputStatus, outputBody)
		}

		logger.Logf(t, "Master UI Status Code:- %s", outputStatus)
		return "", nil
	})
}

// Verify the status of Tserver UI
func testYugaByteTserverURL(t *testing.T, terraformOptions *terraform.Options, tserverUI string, sshSession ssh.Host) {
	statusCodeCheckCmd := fmt.Sprintf("curl -o /dev/null -s -w \"%%{http_code}\\n\" http://%s:9000", tserverUI)
	bodyURLCmd := fmt.Sprintf("curl http://%s:9000", tserverUI)
	retry.DoWithRetry(t, "Checking YB Tserver UI", maxRetries, timeBetweenRetries, func() (string, error) {
		outputStatus, errStatus := ssh.CheckSshCommandE(t, sshSession, statusCodeCheckCmd)
		if errStatus != nil {
			return "", errStatus
		}

		outputBody, errBody := ssh.CheckSshCommandE(t, sshSession, bodyURLCmd)
		if errBody != nil {
			return "", errBody
		}

		if !strings.Contains(string(outputBody), "YugabyteDB") {
			return "", fmt.Errorf("Failed to find the 'YugabyteDB' in output\nStatus Code: %s, Out from Tserver UI: %s", outputStatus, outputBody)
		}

		logger.Logf(t, "Tserver UI Status Code:- %s", outputStatus)
		return "", nil
	})
}

func testYugaByteSSH(t *testing.T, terraformOptions *terraform.Options, sshSession ssh.Host) {
	sshCommand := fmt.Sprintf("echo \"Hello Terratest! I am $(whoami) user at $(hostname)\"")
	retry.DoWithRetry(t, "Attempting to SSH", maxRetries, timeBetweenRetries, func() (string, error) {
		output, err := ssh.CheckSshCommandE(t, sshSession, sshCommand)
		if err != nil {
			return "", err
		}
		logger.Logf(t, "SSH Command Output: %s\n", output)
		return "", nil
	})
}

// Verify the YSQL API
func testYugaByteYSQLSH(t *testing.T, terraformOptions *terraform.Options, privateIP string, sshUser string, sshSession ssh.Host) {
	commandConnectYSQLSH := fmt.Sprintf("/home/%s/yugabyte-db/tserver/bin/ysqlsh --echo-queries -h %s -c \\\\conninfo", sshUser, privateIP)
	retry.DoWithRetry(t, "Conecting YSQLSH", maxRetries, timeBetweenRetries, func() (string, error) {
		output, err := ssh.CheckSshCommandE(t, sshSession, commandConnectYSQLSH)
		if err != nil {
			return "", err
		}
		logger.Logf(t, "Output of Ysql command :- %s", output)
		return "", nil
	})
}

// Verify the YCQL API
func testYugaByteCQLSH(t *testing.T, terraformOptions *terraform.Options, privateIP string, sshUser string, sshSession ssh.Host) {
	commandConnectCQLSH := fmt.Sprintf("/home/%s/yugabyte-db/tserver/bin/ycqlsh %s 9042 --execute 'SHOW HOST'", sshUser, privateIP)
	retry.DoWithRetry(t, "Conecting YCQLSH", maxRetries, timeBetweenRetries, func() (string, error) {
		output, err := ssh.CheckSshCommandE(t, sshSession, commandConnectCQLSH)
		if err != nil {
			return "", err
		}
		logger.Logf(t, "Output of Ycql command :- %s", output)
		return "", nil
	})
}

// Verify Master and Tserver conf exists or not. If exists then prints its Value.
func testYugaByteConf(t *testing.T, terraformOptions *terraform.Options, sshUser string, yugabyteDir string, sshSession ssh.Host) {
	masterConf := fmt.Sprintf("/home/%s/yugabyte-db/master/conf/server.conf", sshUser)
	tserverConf := fmt.Sprintf("/home/%s/yugabyte-db/tserver/conf/server.conf", sshUser)

	fdMasterConf, errFDMasterConf := os.Create(fmt.Sprintf("%s/master-server.conf", yugabyteDir))
	if errFDMasterConf != nil {
		t.Fatalf("Unable to create file descriptor for Master Conf%s", errFDMasterConf)
	}

	fdTserverConf, errFDTserverConf := os.Create(fmt.Sprintf("%s/tserver-server.conf", yugabyteDir))
	if errFDTserverConf != nil {
		t.Fatalf("Unable to create file descriptor for Tserver Conf%s", errFDTserverConf)
	}

	if getMasterFileError := ssh.ScpFileFromE(t, sshSession, masterConf, fdMasterConf, false); getMasterFileError != nil {
		t.Fatalf("We got error while getting file from server :- Master: %s", getMasterFileError)
	}

	if getTserverFileError := ssh.ScpFileFromE(t, sshSession, tserverConf, fdTserverConf, false); getTserverFileError != nil {
		t.Fatalf("We got error while getting file from server :- Tserver: %s", getTserverFileError)
	}

	outputMasterConf := ssh.CheckSshCommand(t, sshSession, fmt.Sprintf("cat /home/%s/yugabyte-db/master/conf/server.conf", sshUser))
	outputTserverConf := ssh.CheckSshCommand(t, sshSession, fmt.Sprintf("cat /home/%s/yugabyte-db/tserver/conf/server.conf", sshUser))
	logger.Logf(t, "Master Conf:\n%s", outputMasterConf)
	logger.Logf(t, "Tserver Conf:\n%s", outputTserverConf)
}

// Check Tserver process is running or not
func testYugaByteProcess(t *testing.T, terraformOptions *terraform.Options, sshSession ssh.Host) {
	// Enhancement - Verify Master Process status
	// Challenge - Terraform unaware of the nodes which behave as the Master and master process only exists on a subset of the nodes.
	// checkMasterProcess := "pgrep --list-name 'yb-master'"
	checkTserverProcess := "pgrep --list-name 'yb-tserver'"
	retry.DoWithRetry(t, "Checking process ", maxRetries, timeBetweenRetries, func() (string, error) {
		// Enhancement - Verify Master Process status
		// outputMasterProcess, errMasterProcess := ssh.CheckSshCommandE(t, sshSession, checkMasterProcess)
		outputTserverProcess, errTserverProcess := ssh.CheckSshCommandE(t, sshSession, checkTserverProcess)
		if errTserverProcess != nil {
			return "", fmt.Errorf("Error Tserver Process: %s", errTserverProcess)
		}
		if !strings.Contains(string(outputTserverProcess), "yb-tserver") {
			return "", fmt.Errorf("Process: %s", outputTserverProcess)
		}
		return "", nil
	})
}

// Check Tserver logfile exists or not
func testYugaByteLogFile(t *testing.T, terraformOptions *terraform.Options, sshUser string, sshSession ssh.Host) {
	// Enhancement - Verify the Master Logfile exists or not
	// Challenge - Terraform unaware of the nodes which behave as the Master and master log file only exists on a subset of the nodes.
	// logMasterDir := fmt.Sprintf("/home/%s/yugabyte-db/master/", sshUser)
	logTserverDir := fmt.Sprintf("/home/%s/yugabyte-db/tserver/", sshUser)
	retry.DoWithRetry(t, "Checking log files", maxRetries, timeBetweenRetries, func() (string, error) {
		// Enhancement - Verify the Master Logfile exists or not
		// outputMasterDir, errMasterDir := ssh.CheckSshCommandE(t, sshSession, fmt.Sprintf("ls %s | grep 'master.'", logMasterDir))
		outputTserverDir, errTserverDir := ssh.CheckSshCommandE(t, sshSession, fmt.Sprintf("ls %s | grep 'tserver.'", logTserverDir))
		if errTserverDir != nil {
			return "", fmt.Errorf("Error Tserver Logfile: %s", errTserverDir)
		}
		if !strings.Contains(string(outputTserverDir), ".out") {
			return "", fmt.Errorf("Log files: %s", outputTserverDir)
		}
		return "", nil
	})
}

// Verify the Ulimit configuration of node
func testYugaByteNodeUlimit(t *testing.T, terraformOptions *terraform.Options, sshSession ssh.Host) {
	ulimitCommand := "ulimit -a"
	retry.DoWithRetry(t, "Checking Ulimits", maxRetries, timeBetweenRetries, func() (string, error) {
		output, err := ssh.CheckSshCommandE(t, sshSession, ulimitCommand)
		if err != nil {
			return "", err
		}

		rePendingSignals := regexp.MustCompile("pending signals.*119934")
		reOpenFiles := regexp.MustCompile("open files.*1048576")
		reMaxUserProcess := regexp.MustCompile("max user processes.*12000")

		if !rePendingSignals.MatchString(output) || !reOpenFiles.MatchString(output) || !reMaxUserProcess.MatchString(output) {
			return "", fmt.Errorf("Output of ulimit -a: %s", output)
		}
		return "", nil
	})
}
