package com.local.billbox.engine

/**
 * Which BillBox this is (services/license.js): "public" = the app on the website (live licences and payments),
 * "admin" = the owner's test build (test licences, Razorpay test mode). The admin build is made with
 * `EDITION=admin ./build.sh apk`, which writes "admin" here for that build only.
 */
object Edition {
    const val NAME = "public"
}
