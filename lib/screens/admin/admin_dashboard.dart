import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../auth/login_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/epic_week_header.dart';

class AdminDashboard extends StatefulWidget {
  final UserModel user;
  const AdminDashboard({super.key, required this.user});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          EpicWeekHeader(userName: widget.user.name, userRole: 'Admin'),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestoreService.getProjects(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.deepOrange),
                  );
                }

                final projects = snapshot.data?.docs ?? [];

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeaderStats(projects),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _showAddProjectDialog,
                        icon: const Icon(Icons.add),
                        label: const Text(
                          'Add New Project',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'All Projects',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (projects.isEmpty)
                      Center(
                        child: Column(
                          children: [
                            const SizedBox(height: 32),
                            Icon(
                              Icons.construction,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No projects yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap "Add New Project" to get started',
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                          ],
                        ),
                      )
                    else
                      ...projects.map((doc) {
                        Map<String, dynamic> data =
                            doc.data() as Map<String, dynamic>;
                        return _buildProjectCard(doc.id, data);
                      }),

                    const SizedBox(height: 32),
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.85,
                        child: GestureDetector(
                          onTap: _logout,
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.grey[700],
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withValues(alpha: 0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'sign out',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStats(List<QueryDocumentSnapshot> projects) {
    int totalProjects = projects.length;
    int activeProjects = projects.where((doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      return data['status'] == 'active';
    }).length;
    int completedProjects = totalProjects - activeProjects;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepOrange,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Company Overview',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                label: 'Total',
                value: totalProjects.toString(),
                icon: Icons.business,
              ),
              _buildStatItem(
                label: 'Active',
                value: activeProjects.toString(),
                icon: Icons.play_circle,
              ),
              _buildStatItem(
                label: 'Done',
                value: completedProjects.toString(),
                icon: Icons.check_circle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildProjectCard(String projectId, Map<String, dynamic> data) {
    String name = data['name'] ?? 'Unknown Project';
    String location = data['location'] ?? 'Unknown Location';
    String status = data['status'] ?? 'active';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: status == 'active' ? Colors.deepOrange : Colors.grey,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        location,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _toggleProjectStatus(projectId, status),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditProjectDialog(projectId, data),
                    icon: const Icon(
                      Icons.edit,
                      color: Colors.deepOrange,
                      size: 18,
                    ),
                    label: const Text(
                      'Edit',
                      style: TextStyle(color: Colors.deepOrange),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.deepOrange),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleProjectStatus(projectId, status),
                    icon: Icon(
                      status == 'active'
                          ? Icons.pause_circle
                          : Icons.play_circle,
                      color: status == 'active' ? Colors.orange : Colors.green,
                      size: 18,
                    ),
                    label: Text(
                      status == 'active' ? 'Pause' : 'Activate',
                      style: TextStyle(
                        color: status == 'active'
                            ? Colors.orange
                            : Colors.green,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: status == 'active'
                            ? Colors.orange
                            : Colors.green,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddProjectDialog() {
    final nameController = TextEditingController();
    final locationController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Add New Project',
          style: TextStyle(color: Colors.deepOrange),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Project Name',
                  hintText: 'e.g. Smith Kitchen Remodel',
                  prefixIcon: const Icon(Icons.business),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                decoration: InputDecoration(
                  labelText: 'Location',
                  hintText: 'e.g. Costa Mesa, CA',
                  prefixIcon: const Icon(Icons.location_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty ||
                  locationController.text.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Please fill in all fields!'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final navigator = Navigator.of(dialogContext);

              await _firestoreService.addProject(
                name: nameController.text.trim(),
                location: locationController.text.trim(),
              );

              navigator.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add Project'),
          ),
        ],
      ),
    );
  }

  void _showEditProjectDialog(String projectId, Map<String, dynamic> data) {
    final nameController = TextEditingController(text: data['name']);
    final locationController = TextEditingController(text: data['location']);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Edit Project',
          style: TextStyle(color: Colors.deepOrange),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Project Name',
                  prefixIcon: const Icon(Icons.business),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                decoration: InputDecoration(
                  labelText: 'Location',
                  prefixIcon: const Icon(Icons.location_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(dialogContext);

              await _firestoreService.updateProject(
                projectId: projectId,
                name: nameController.text.trim(),
                location: locationController.text.trim(),
              );

              navigator.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleProjectStatus(
    String projectId,
    String currentStatus,
  ) async {
    String newStatus = currentStatus == 'active' ? 'completed' : 'active';
    await _firestoreService.updateProjectStatus(
      projectId: projectId,
      status: newStatus,
    );
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    await _authService.signOut();
    navigator.pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }
}
