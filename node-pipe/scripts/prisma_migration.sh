# prisma_migration.sh
#!/bin/bash

SERVICE=$1
APP_ENV=$2
SEED=$3

SPN=""
KTAB=""
export PRISMA_QUERY_ENGINE_LIBRARY=~/engines/libquery_engine.so
export PRISMA_SCHEMA_ENGINE_BINARY=~/engines/schema-engine


case "$APP_ENV" in
  "dev")
    case $SERVICE in
      "apiloandetails")
        export DATABASE_URL="sqlserver://EC2-SQLREPDEV01.office.local:7331;database=Loan_Details;encrypt=true;integratedSecurity=true;trustServerCertificate=true;"
        SPN="MsSqlSvc/SVCMALOANDBDEV01DDL.office.local@OFFICE.LOCAL"
        KTAB="/etc/krb5.keytab.apiloandetailsdev"
        ;;
      "apicommunications")
        export DATABASE_URL="sqlserver://EC2-SQLREPDEV01.office.local:7331;database=Communications;encrypt=true;integratedSecurity=true;trustServerCertificate=true;"
        SPN="MsSqlSvc/SVCPRICOMDBDEV01.office.local@OFFICE.LOCAL"
        KTAB="/etc/krb5.keytab.apicommunicationsdev"
        ;;
      "apipricing")
        export DATABASE_URL="sqlserver://EC2-SQLREPDEV01.office.local:7331;database=Pricing;encrypt=true;integratedSecurity=true;trustServerCertificate=true;"
        SPN="MsSqlSvc/SVCPRCREPDPRCINGDDL.office.local@OFFICE.LOCAL"
        KTAB="/etc/krb5.keytab.apipricingdev"
        ;;
      *)
        echo "Unknown service name"
        ;;
    esac
    ;;
  "test")
    case $SERVICE in
      "apiloandetails")
        ;;
      "apicommunications")
        export DATABASE_URL="sqlserver://EC2-SQLREPTST01.office.local:7331;database=Communications;encrypt=true;integratedSecurity=true;trustServerCertificate=true;"
        SPN="MsSqlSvc/SVCPRICOMDBTST01.office.local@OFFICE.LOCAL"
        KTAB="/etc/krb5.keytab.apicommunicationstest"
        ;;
      "apipricing")
        export DATABASE_URL="sqlserver://EC2-SQLREPTST01.office.local:7331;database=Pricing;encrypt=true;integratedSecurity=true;trustServerCertificate=true;"
        SPN="MsSqlSvc/SVCPRCREPTPRCINGDDL.office.local@OFFICE.LOCAL"
        KTAB="/etc/krb5.keytab.apipricingtest"
        ;;
      *)
        echo "Unknown service name"
        ;;
    esac
    ;;
  "qa")
    case $SERVICE in
      "apiloandetails")
        ;;
      "apicommunications")
        export DATABASE_URL="sqlserver://SQLAPIQALIST.office.local:7331;database=Communications;encrypt=true;integratedSecurity=true;trustServerCertificate=true;"
        SPN="MsSqlSvc/SVCPRICOMDBQA01.office.local@OFFICE.LOCAL"
        KTAB="/etc/krb5.keytab.apicommunicationsqa"
        ;;
      "apipricing")
        export DATABASE_URL="sqlserver://SQLAPIQALIST.office.local:7331;database=Pricing;encrypt=true;integratedSecurity=true;trustServerCertificate=true;"
        SPN="MsSqlSvc/SVCPRCAPIQAPRCINGDDL.office.local@OFFICE.LOCAL"
        KTAB="/etc/krb5.keytab.apipricingqa"
        ;;
      *)
        echo "Unknown service name"
        ;;
    esac
    ;;
  *)
    echo "Invalid environment. Please use 'dev', 'test', 'qa', or 'prod'."
    exit 1
    ;;
esac

/usr/bin/kdestroy

/usr/bin/kinit -kt $KTAB $SPN

npm run prisma:migration:deploy

npm run prisma:generate
if [ $SEED = true ] ; then
  npm run prepare:test
  npm run prisma:seed
fi
