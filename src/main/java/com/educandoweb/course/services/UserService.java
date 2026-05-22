package com.educandoweb.course.services;

import java.util.List;
import java.util.Optional;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import com.educandoweb.course.entities.User;
import com.educandoweb.course.repositories.UserRepository;
import com.educandoweb.course.services.exceptions.DatabaseException;
import com.educandoweb.course.services.exceptions.ResourceNotFoundException;

@Service
public class UserService {
	
	private UserRepository repository;
	
	public UserService(UserRepository repository) {
		this.repository = repository;
	}
	
	public List<User> findAll() {
		return repository.findAll();
	}
	
	public User findById(Long id) {
		Optional<User> obj = repository.findById(id);
		return obj.orElseThrow(() -> new ResourceNotFoundException(id));
	}
	
	public User insert(User obj) {
		return repository.save(obj);
	}
	
	public void delete(Long id) {
		// 1. Verifica se o ID realmente existe no banco
	    if (!repository.existsById(id)) {
	        throw new ResourceNotFoundException(id);
	    }
	    // 2. Se chegou aqui, existe e tenta deletar
	    try {
	        repository.deleteById(id);
	    } catch (DataIntegrityViolationException e) {
	        // Esse catch ainda captura se você tentar deletar um usuário 
	        // que possui pedidos atrelados a ele (erro de chave estrangeira)
	    	throw new DatabaseException(e.getMessage());
	    }	
	}
	
	public User update(Long id, User obj) {
		User entity = repository.getReferenceById(id);
		updateData(entity, obj);
		return entity;
	}

	private void updateData(User entity, User obj) {
		entity.setName(obj.getName());
		entity.setEmail(obj.getEmail());
		entity.setPhone(obj.getPhone());
	}
	
	
}
