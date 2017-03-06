def config = [
    appName: 'logstash-output-adls',
    mails: 'nosi.metadata@nos.pt'
]

try {
    currentBuild.displayName = "${config.appName}-${currentBuild.number}"
    currentBuild.description = env.BRANCH_NAME

    node('dev && linux') {
        stage('build') {
            checkout scm

           // buildVersion and commit capture - Uses pcre regex
            def versionRegexPattern = "s\\.version.*=.*'\\K(.*)(?=')"
            env.BuildVersion = sh(returnStdout: true, script: "cat logstash-output-adls.gemspec | grep -Po \"${versionRegexPattern}\"").trim()
            env.GIT_COMMIT = sh(returnStdout: true, script: "git rev-parse --verify HEAD").trim()
            env.GIT_COUNT = sh(returnStdout: true, script: "git rev-list --all --count").trim()
            writeFile file: 'build.properties', text: """BuildVersion=${env.BuildVersion}\nGitCommit=${env.GIT_COMMIT}\nBuildVersionRevision=${env.GIT_COUNT}"""
            currentBuild.displayName = "${env.BuildVersion}-${env.GIT_COUNT}"
            
            // build
            sh "${tool 'jruby'} -S gem install bundler"
            sh "${tool 'jruby'} -S bundle install"
            sh "${tool 'jruby'} -S rake install_jars"
            sh "${tool 'jruby'} -S gem build logstash-output-adls.gemspec"

            // archive
            def artifacts = 'build.properties,logstash-output-adls-*.gem'
            archiveArtifacts artifacts: artifacts, caseSensitive: false
            fingerprint 'build.properties'
            stash(name:'artifacts', includes: artifacts)
        }

        stage('tests & quality') {
            // returnStatus prevents throw when exitcode != 0
            sh(returnStatus:true, script: "${tool 'jruby'} -S rspec spec/outputs/adls_spec.rb --format RspecJunitFormatter --out testresult.junit.xml")
            step([$class: 'XUnitPublisher', testTimeMargin: '3000', thresholdMode: 1, thresholds: [[$class: 'FailedThreshold', failureNewThreshold: '', failureThreshold: '', unstableNewThreshold: '', unstableThreshold: '0'], [$class: 'SkippedThreshold', failureNewThreshold: '', failureThreshold: '', unstableNewThreshold: '', unstableThreshold: '']], tools: [[$class: 'JUnitType', deleteOutputFiles: true, failIfNotNew: true, pattern: 'testresult.junit.xml', skipNoTestFiles: false, stopProcessingIfError: true]]])
        }

        // Don't go any further if the build is UNSTABLE
        if(currentBuild.result == "UNSTABLE") {
            return;
        }

        stage('deploy:gem') {
            sh "${tool 'jruby'} -S gem push logstash-output-adls-*.gem"
        }
    }
} finally {
    node {
        step([$class: "Mailer", notifyEveryUnstableBuild: true, recipients: "${config.mails}", sendToIndividuals: false])
    }
}