#!/usr/bin/ruby -w

require 'optparse'
require 'socket'

# Configuration par défaut
options = { racine: '/', port: 9100, services: ['ssh', 'cron', 'docker'] }
OptionParser.new do |opts|
  opts.on("-r", "--racine RACINE", "Répertoire racine") { |r| options[:racine] = r }
  opts.on("-p", "--port PORT", Integer, "Port HTTP") { |p| options[:port] = p }
end.parse!

def collecter_metriques(racine, services)
  metriques = ""

  # 1. Charge moyenne
  begin
    loadavg = File.read("#{racine}proc/loadavg").split
    metriques += "# HELP audit_load_average Charge moyenne\n# TYPE audit_load_average gauge\n"
    metriques += "audit_load_average{period=\"1m\"} #{loadavg[0]}\n"
    metriques += "audit_load_average{period=\"5m\"} #{loadavg[1]}\n"
  rescue
  end

# 2. CPU (ticks cumulés pour le calcul rate dans Prometheus)
  begin
    cpu_lignes = File.read("#{racine}proc/stat").lines.find { |l| l.start_with?("cpu ") }.split
    metriques += "# HELP audit_cpu_ticks_total Temps CPU cumulé\n# TYPE audit_cpu_ticks_total counter\n"
    metriques += "audit_cpu_ticks_total{mode=\"user\"} #{cpu_lignes[1]}\n"
    metriques += "audit_cpu_ticks_total{mode=\"system\"} #{cpu_lignes[3]}\n"
    metriques += "audit_cpu_ticks_total{mode=\"idle\"} #{cpu_lignes[4]}\n"
  rescue
  end

  # 3. Statut des services (1 = actif, 0 = inactif)
  metriques += "# HELP audit_service_active Statut des services critiques\n# TYPE audit_service_active gauge\n"
  services.each do |service|
    actif = `systemctl is-active #{service} 2>/dev/null`.strip == 'active' ? 1 : 0
    metriques += "audit_service_active{service=\"#{service}\"} #{actif}\n"
  end

  # 4. Mémoire (lecture propre de meminfo)
  begin
    meminfo = File.read("#{racine}proc/meminfo")
    total_kb = meminfo.match(/^MemTotal:\s+(\d+)/)[1].to_i
    dispo_kb = meminfo.match(/^MemAvailable:\s+(\d+)/)[1].to_i
    
    metriques += "# HELP audit_memory_bytes RAM en octets\n# TYPE audit_memory_bytes gauge\n"
    metriques += "audit_memory_bytes{type=\"total\"} #{total_kb * 1024}\n"
    metriques += "audit_memory_bytes{type=\"utilise\"} #{(total_kb - dispo_kb) * 1024}\n"
  rescue
  end

  # 5. Disques (ciblage direct de la racine pour éviter les doublons)
  begin
    df_out = `df -B1 -P #{racine} 2>/dev/null`.split("\n")
    
    if df_out.size > 1
      cols = df_out[1].split
      metriques += "# HELP audit_disk_bytes Espace disque\n# TYPE audit_disk_bytes gauge\n"
      metriques += "audit_disk_bytes{type=\"total\"} #{cols[1]}\n"
      metriques += "audit_disk_bytes{type=\"utilise\"} #{cols[2]}\n"
    end
  rescue
  end
  
  return metriques
end

# Lancement du serveur HTTP
server = TCPServer.new('0.0.0.0', options[:port])
puts "Agent démarré sur le port #{options[:port]}..."

loop do
  client = server.accept
  request = client.gets
  
  if request && request.start_with?("GET /metrics")
    client.print "HTTP/1.1 200 OK\r\nContent-Type: text/plain; version=0.0.4\r\n\r\n"
    client.print collecter_metriques(options[:racine], options[:services])
  else
    client.print "HTTP/1.1 404 Not Found\r\n\r\n"
  end
  client.close
end