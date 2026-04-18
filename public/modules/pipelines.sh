#!/bin/bash

setup_pipelines() {

  log "🚀 Configurando pipelines do Jenkins..."

  local JENKINS_DIR="/root/jenkins"
  local APPS_DIR="/root/envs/apps"

  ensure_dir "$JENKINS_DIR/init.groovy.d"

  log "Criando script Groovy de pipelines..."

  cat <<'EOF' > "$JENKINS_DIR/init.groovy.d/pipelines.groovy"
import com.coravy.hudson.plugins.github.GithubProjectProperty
import com.cloudbees.jenkins.GitHubPushTrigger
import org.jenkinsci.plugins.workflow.job.*
import org.jenkinsci.plugins.workflow.cps.*
import hudson.plugins.git.*
import jenkins.model.*

import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import hudson.util.Secret

def jenkins = Jenkins.instance

def store = jenkins.getExtensionList(
  'com.cloudbees.plugins.credentials.SystemCredentialsProvider'
)[0].getStore()

def secrets = [:]

// ========================
// 🔐 LÊ SECRETS
// ========================
new File("/root/envs/apps").eachFile { file ->
    file.eachLine { line ->
        def parts = line.split(":").collect { it.trim() }

        if (parts.size() >= 10) {
            def project = parts[1]
            def secret = parts[6]
            secrets[project] = secret
        } else {
            println("⚠️ Linha inválida ignorada: " + line)
        }
    }
}

// ========================
// 🔐 CRIA CREDENTIALS
// ========================
secrets.each { name, value ->

  def id = "webhook-${name}"

  if (store.getCredentials(Domain.global()).find { it.id == id }) {
      println("⚠️ Credencial já existe: " + id)
  } else {

      def cred = new StringCredentialsImpl(
        CredentialsScope.GLOBAL,
        id,
        "Webhook secret for ${name}",
        Secret.fromString(value)
      )

      store.addCredentials(Domain.global(), cred)
      println("🔐 Credencial criada: " + id)
  }
}

// ========================
// 🚀 CRIA PIPELINE
// ========================
def createPipeline(jobName, repo, branch) {

    if (!repo || repo.trim().isEmpty()) {
        println("❌ Repo inválido para " + jobName)
        return
    }

    if (jenkins.getItem(jobName) != null) {
        println("⚠️ Job já existe: " + jobName)
        return
    }

    println("📦 Criando pipeline: " + jobName + " | repo=" + repo + " | branch=" + branch)

    def job = jenkins.createProject(WorkflowJob, jobName)

    def scm = new GitSCM(repo)
    scm.branches = [new BranchSpec("*/" + branch)]

    def defn = new CpsScmFlowDefinition(scm, "Jenkinsfile")
    job.setDefinition(defn)
    job.setConcurrentBuild(false)

    job.addProperty(new GithubProjectProperty(repo))
    job.addTrigger(new GitHubPushTrigger())

    job.save()

    println("✅ Job criado: " + jobName + " (" + branch + ")")

    // 🚀 FIRST RUN
    job.scheduleBuild2(0)
    println("🔥 Primeiro build disparado: " + jobName)
}

// ========================
// 📦 LÊ PROJETOS (.apps)
// ========================
println("🚀 Criando pipelines...")

new File("/root/envs/apps").eachFile { file ->

    file.eachLine { line ->

        def parts = line.split(":").collect { it.trim() }

        if (parts.size() >= 10) {

            def type = parts[0]
            def name = parts[1]
            def repo = parts[7]
            def prod = parts[8]
            def dev = parts[9]

            if (type == "root") {
                createPipeline(name, repo, prod)
            }

            if (type == "dev") {
                createPipeline(name, repo, dev)
            }

        } else {
            println("⚠️ Linha inválida ignorada: " + line)
        }
    }
}

println("🎉 Pipelines criados com sucesso")
EOF

  success "Pipelines configurados"
}
