#! /usr/bin/env bats

load '/bats-support/load.bash'
load '/bats-assert/load.bash'
load '/getssl/test/test_helper.bash'


# This is run for every test
setup() {
    [ ! -f $BATS_RUN_TMPDIR/failed.skip ] || skip "skipping tests after first failure"
    export CURL_CA_BUNDLE=/root/pebble-ca-bundle.crt
    if [ -n "${VSFTPD_CONF}" ]; then
        if [ ! -f "${VSFTPD_CONF}.getssl" ]; then
            cp $VSFTPD_CONF ${VSFTPD_CONF}.getssl
        else
            cp ${VSFTPD_CONF}.getssl $VSFTPD_CONF
        fi

        # enable passive and disable active mode
        # https://www.pixelstech.net/article/1364817664-FTP-active-mode-and-passive-mode
        cat <<- _FTP >> $VSFTPD_CONF
pasv_enable=YES
pasv_max_port=10100
pasv_min_port=10090
_FTP
    fi
}


teardown() {
    [ -n "$BATS_TEST_COMPLETED" ] || touch $BATS_RUN_TMPDIR/failed.skip
    if [ -n "${VSFTPD_CONF}" ]; then
        cp ${VSFTPD_CONF}.getssl $VSFTPD_CONF
        ${CODE_DIR}/test/restart-ftpd stop
    fi
}



@test "Use ftpes, FTP_PORT=1001 (explicit ssl, port 1001) to create challenge file" {
    if [[ ! -f /etc/vsftpd.pem ]]; then
        echo "FAILED: This test requires the previous test to succeed"
        exit 1
    fi

    if [ -n "$STAGING" ]; then
        skip "Using staging server, skipping internal test"
    fi

    if [[ ! -d /var/www/html/.well-known/acme-challenge ]]; then
        mkdir -p /var/www/html/.well-known/acme-challenge
    fi

    # Restart vsftpd with ssl enabled
    cat <<- _FTP >> $VSFTPD_CONF
connect_from_port_20=NO
listen_port=1001
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=NO
force_local_logins_ssl=NO
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
require_ssl_reuse=NO
ssl_ciphers=HIGH
rsa_cert_file=/etc/vsftpd.pem
rsa_private_key_file=/etc/vsftpd.pem
_FTP
    ${CODE_DIR}/test/restart-ftpd start

    # Always change ownership and permissions in case previous tests created the directories as root
    chgrp -R www-data /var/www/html/.well-known
    chmod -R g+w /var/www/html/.well-known

    CONFIG_FILE="getssl-http01.cfg"
    setup_environment
    init_getssl

    # Verbose output is needed so the test assertion passes
    # On Ubuntu 14 and 18 curl errors with "unable to get issuer certificate" so disable cert check using "-k"
    if [[ "$GETSSL_OS" == "ubuntu14" || "$GETSSL_OS" == "ubuntu18" ]]; then
        cat <<- EOF > ${INSTALL_DIR}/.getssl/${GETSSL_CMD_HOST}/getssl_test_specific.cfg
    ACL="ftpes:ftpuser:ftpuser:${GETSSL_CMD_HOST}:/var/www/html/.well-known/acme-challenge"
    FTPS_OPTIONS="--cacert /etc/cacert.pem -v -k"
    FTP_PORT=1001
EOF
    else
        cat <<- EOF > ${INSTALL_DIR}/.getssl/${GETSSL_CMD_HOST}/getssl_test_specific.cfg
ACL="ftpes:ftpuser:ftpuser:${GETSSL_CMD_HOST}:/var/www/html/.well-known/acme-challenge"
FTPS_OPTIONS="--cacert /etc/cacert.pem -v"
FTP_PORT=1001
EOF
    fi

    create_certificate
    assert_success
    # assert_line --partial "SSL connection using TLSv1.3"
    assert_line --partial "200 PROT now Private"

    check_output_for_errors
}


@test "Use ftps, FTP_PORT=2002 (implicit ssl, port 2002) to create challenge file" {
    if [[ ! -f /etc/vsftpd.pem ]]; then
        echo "FAILED: This test requires the previous test to succeed"
        exit 1
    fi

    if [ -n "$STAGING" ]; then
        skip "Using staging server, skipping internal test"
    fi

    # Restart vsftpd listening on port 990
    cat <<- _FTP >> $VSFTPD_CONF
implicit_ssl=YES
listen_port=2002
connect_from_port_20=NO
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=NO
force_local_logins_ssl=NO
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
require_ssl_reuse=NO
ssl_ciphers=HIGH
rsa_cert_file=/etc/vsftpd.pem
rsa_private_key_file=/etc/vsftpd.pem
_FTP
    ${CODE_DIR}/test/restart-ftpd start

    if [[ ! -d /var/www/html/.well-known/acme-challenge ]]; then
        mkdir -p /var/www/html/.well-known/acme-challenge
    fi

    # Always change ownership and permissions in case previous tests created the directories as root
    chgrp -R www-data /var/www/html/.well-known
    chmod -R g+w /var/www/html/.well-known

    CONFIG_FILE="getssl-http01.cfg"
    setup_environment
    init_getssl

    # Verbose output is needed so the test assertion passes
    # On Ubuntu 14 and 18 curl errors with "unable to get issuer certificate" so disable cert check using "-k"
    # as I don't have time to fix
    if [[ "$GETSSL_OS" == "ubuntu14" || "$GETSSL_OS" == "ubuntu18" ]]; then
        cat <<- EOF > ${INSTALL_DIR}/.getssl/${GETSSL_CMD_HOST}/getssl_test_specific.cfg
ACL="ftps:ftpuser:ftpuser:${GETSSL_CMD_HOST}:/var/www/html/.well-known/acme-challenge"
FTPS_OPTIONS="--cacert /etc/cacert.pem -v -k"
FTP_PORT=2002
EOF
    else
        cat <<- EOF > ${INSTALL_DIR}/.getssl/${GETSSL_CMD_HOST}/getssl_test_specific.cfg
ACL="ftps:ftpuser:ftpuser:${GETSSL_CMD_HOST}:/var/www/html/.well-known/acme-challenge"
FTPS_OPTIONS="--cacert /etc/cacert.pem -v"
FTP_PORT=2002
EOF
    fi

    create_certificate
    assert_success
    assert_line --partial "200 PROT now Private"
    check_output_for_errors
}
